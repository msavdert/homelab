# 06 Storage

## What this adds

A PersistentVolumeClaim gets a volume without any extra setting: the
default StorageClass `local-path` creates a directory on the data disk of
the node where the pod is scheduled. The data survives a restart of the
pod and a reboot of the node.

```
PVC (storageClassName unset -> local-path, the default)
  -> pod scheduled to a node (WaitForFirstConsumer)
  -> local-path-provisioner creates /var/mnt/local-path-provisioner/<pv>_<ns>_<pvc>
     on that node, through a short-lived helper pod
  -> PV of type hostPath with node affinity to that node
  -> /var/mnt/local-path-provisioner = /dev/sdb1, XFS, the whole 100 GB data disk
     (Talos user volume local-path-provisioner)
```

**A volume belongs to one node.** The PV carries node affinity, so its pod
can only run on the node that holds the data. What that means:

- **Reboot or upgrade of the node.** The pod waits, then starts again on
  the same node with its data. Shown by the gate below.
- **Drain.** `kubectl drain` evicts the pod; it stays `Pending` until the
  node is uncordoned, because no other node can mount the volume. A
  single-replica application is down for that time. Assumption, from the
  PV's node affinity, not run here: drain does not need
  `--delete-emptydir-data` for these volumes, since they are hostPath, not
  emptyDir.
- **Loss of the node or its disk.** The data is gone. Nothing is
  replicated, and there are no CSI snapshots. Data that matters is copied
  elsewhere by the application itself: CloudNativePG keeps one instance
  per node and backs up to object storage (D15, phase 7).

## Before you start

- [03 Flux](03-flux.md): Flux reconciles `kubernetes/apps/` from `main`.
- Each node has a second, empty disk `/dev/sdb` (100 GiB, created by
  OpenTofu in phase 1). `talosctl -n <ip> get discoveredvolumes` shows it
  without partitions or filesystem.

## Steps

### 1. The data volume (Talos)

`talos/patches/cluster.yaml` holds a `UserVolumeConfig`:

```yaml
apiVersion: v1alpha1
kind: UserVolumeConfig
name: local-path-provisioner
provisioning:
  diskSelector:
    match: "!system_disk"
  minSize: 50GB
```

It selects the one disk that is not the system disk and large enough
(the cloud-init CD-ROM is 4 MB), creates one partition over all of it,
formats it XFS and mounts it at `/var/mnt/local-path-provisioner` with
`nosuid,nodev,noexec`. The selector does not name `/dev/sdb`, because
device names can change between boots (D35). Apply it node by node; no
reboot is needed:

```
mise run talos:apply k8s-1 --dry-run   # diff: only the UserVolumeConfig
mise run talos:apply k8s-1             # "Applied configuration without a reboot"
talosctl -n 10.0.6.11 get mountstatus u-local-path-provisioner
```

then `k8s-2` and `k8s-3`. On a new cluster the volume is in the machine
configuration from the start.

### 2. The provisioner (Flux)

```
kubernetes/apps/local-path-storage/
  namespace.yaml                      pod-security enforce: privileged
  local-path-provisioner/
    ks.yaml                           Flux Kustomization, wait: true
    app/
      ocirepository.yaml              chart 0.0.37 from ghcr.io/rancher/...
      helmrelease.yaml                values from the generated ConfigMap
      values.yaml                     path, default class, helper image
      kustomization.yaml, kustomizeconfig.yaml
```

- The namespace is `privileged` because the helper pods mount host paths,
  which the default pod security level refuses (Sidero local storage
  guide).
- `values.yaml` sets the path for every node
  (`DEFAULT_PATH_FOR_NON_LISTED_NODES`), makes `local-path` the default
  StorageClass and pins the helper image (the chart default is
  `busybox:latest`). The class keeps the chart's `reclaimPolicy: Delete`
  and `volumeBindingMode: WaitForFirstConsumer`.
- Values reach the HelmRelease as in Cilium (D32): a changed
  `values.yaml` changes the ConfigMap name and starts an upgrade at once.

Merging the pull request is the deployment. Check:

```
$ flux get hr -n local-path-storage
NAME                    REVISION  SUSPENDED  READY  MESSAGE
local-path-provisioner  0.0.37    False      True   Helm install succeeded for release local-path-storage/local-path-provisioner.v1 with chart local-path-provisioner@0.0.37

$ kubectl get sc
NAME                   PROVISIONER                            RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   cluster.local/local-path-provisioner   Delete          WaitForFirstConsumer   true                   18s
```

## Check

Run on 2026-11-16, UTC, after pull request #24 was merged. The test
manifest (a 1Gi PVC and a busybox pod, as a non-root user, that writes
the time to `/data/proof` once) was applied by hand and is not
committed.

```
$ talosctl -n 10.0.6.11 get mountstatus u-local-path-provisioner   # same on .12 and .13
NODE        NAMESPACE   TYPE          ID                         VERSION   SOURCE      TARGET                            FILESYSTEM   VOLUME
10.0.6.11   runtime     MountStatus   u-local-path-provisioner   2         /dev/sdb1   /var/mnt/local-path-provisioner   xfs          u-local-path-provisioner

$ kubectl apply -f storage-test.yaml
persistentvolumeclaim/storage-test created
pod/storage-test created
$ kubectl wait --for=condition=Ready pod/storage-test --timeout=3m
pod/storage-test condition met
$ kubectl exec storage-test -- cat /data/proof
2026-11-16T03:21:43Z
$ kubectl get pod storage-test -o wide
NAME           READY   STATUS    RESTARTS   AGE   IP            NODE    ...
storage-test   1/1     Running   0          9s    10.244.1.81   k8s-3   ...
$ kubectl exec storage-test -- df -h /data
Filesystem                Size      Used Available Use% Mounted on
/dev/sdb1                99.9G      1.9G     98.0G   2% /data
$ kubectl get pvc
NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
storage-test   Bound    pvc-81e668aa-1e83-44d4-8008-24be1a339e2f   1Gi        RWO            local-path

$ talosctl -n 10.0.6.13 get mountstatus u-local-path-provisioner
10.0.6.13   runtime     MountStatus   u-local-path-provisioner   2         /dev/sdb1   /var/mnt/local-path-provisioner   xfs          u-local-path-provisioner
$ talosctl -n 10.0.6.13 reboot
"10.0.6.13": post check passed
$ kubectl wait --for=condition=Ready pod/storage-test --timeout=10m
pod/storage-test condition met
$ kubectl exec storage-test -- cat /data/proof
2026-11-16T03:21:43Z
$ kubectl get pod storage-test -o wide
NAME           READY   STATUS    RESTARTS      AGE    IP            NODE    ...
storage-test   1/1     Running   1 (57s ago)   109s   10.244.1.43   k8s-3   ...

$ kubectl delete -f storage-test.yaml
persistentvolumeclaim "storage-test" deleted from default namespace
pod "storage-test" deleted from default namespace
$ kubectl get pv
No resources found
$ talosctl -n 10.0.6.13 ls /var/mnt/local-path-provisioner
.
```

The `df` size shows the data disk (the system disk is 20 GB). The proof
has the same value on the same node after the reboot. Deleting the claim
deleted the PV and its directory.

## Day-two tasks

- **Use a volume.** A PVC without `storageClassName` gets `local-path`.
  Assumption, from the provisioner's README and not tested here: the size
  in the claim is not enforced; every volume on a node shares that node's
  100 GB. `ReadWriteOnce` only.
- **Keep data when a claim is deleted.** The class deletes the directory
  with the claim. For data that must outlive its claim, set
  `persistentVolumeReclaimPolicy: Retain` on the PV by hand
  (`kubectl patch pv <pv> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'`)
  before deleting the claim; the directory then stays on the node.
- **Space.** `kubectl exec` into a pod with a volume and `df -h`, or
  `talosctl -n <ip> usage /var/mnt/local-path-provisioner`.
- **Upgrade.** Renovate proposes the chart tag in `ocirepository.yaml`
  and the helper image in `values.yaml`.
- **Replace a node.** Its volumes are lost; the pods that used them stay
  `Pending` until their claims are deleted and recreated. Restore the data
  from the application's own backup.

## When it goes wrong

- **PVC stays `Pending` with "waiting for first consumer".** Normal until
  a pod uses it. With a pod, `kubectl -n local-path-storage logs
  deploy/local-path-provisioner` shows the provisioning attempt.
- **Helper pod refused by pod security.** The namespace has lost its
  `pod-security.kubernetes.io/enforce: privileged` label
  (`kubectl get ns local-path-storage --show-labels`).
- **Pod `Pending` with "node(s) didn't match PersistentVolume's node
  affinity".** The node that holds the volume is down or cordoned. Bring
  it back; there is no other copy.
- **A program in a volume fails with "permission denied".** The volume is
  mounted `noexec`; data only, no binaries.
- **Volume not mounted after a rebuild.** `talosctl -n <ip> get
  volumestatus u-local-path-provisioner` shows the phase and the error;
  a disk that still carries an old partition table may have to be wiped
  first (`talosctl wipe disk`), which deletes its data.
- **Dozens of failed cilium-operator pods after a node reboot.** Seen
  during this gate: while k8s-3 shut down gracefully the scheduler kept
  placing the replacement operator pod there and the kubelet rejected each
  one (`NodeShutdown`), 45 in about ten seconds. The ReplicaSet recovered
  on its own. Failed pods are not garbage-collected until there are
  thousands; remove them with `kubectl -n kube-system delete pods -l
  name=cilium-operator --field-selector=status.phase=Failed`. This is not
  a storage problem; it will recur on reboots and upgrades.

## Sources

- Sidero, "Local storage":
  https://docs.siderolabs.com/kubernetes-guides/csi/local-storage
- Talos v1.14, `UserVolumeConfig` reference and "User volumes":
  https://docs.siderolabs.com/talos/v1.14/reference/configuration/block/uservolumeconfig
  and
  https://docs.siderolabs.com/talos/v1.14/configure-your-talos-cluster/storage-and-disk-management/disk-management/user
- local-path-provisioner v0.0.37 and its chart (pulled and read: values,
  `templates/deployment.yaml`, `templates/configmap.yaml`):
  https://github.com/rancher/local-path-provisioner
- Decisions D14 and D35 in [Decisions](../decisions.md).
