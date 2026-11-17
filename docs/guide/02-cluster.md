# 02 Cluster

## What this adds

Kubernetes 1.36.6 runs on the three Talos nodes, each one control plane and
worker, with Cilium 1.20.4 as the network plugin and as the replacement for
kube-proxy. The API is reached at `https://10.0.6.10:6443`, a virtual IP that
one node holds at a time and that moves when that node goes away. The
machine configuration is a few patch files in `talos/`; the cluster secrets
live only in 1Password, so the configuration and the credentials can be
rebuilt from any clone.

## Before you start

- [01 Nodes](01-nodes.md): the three VMs in maintenance mode at 10.0.6.11 to
  10.0.6.13.
- A clone with `mise install` done. `mise.toml` sets `TALOSCONFIG`,
  `KUBECONFIG` and `KUBERNETES_VERSION` for every command run inside the
  clone. Outside mise (a plain shell), export the first two by hand:
  `export TALOSCONFIG=$PWD/talosconfig KUBECONFIG=$PWD/kubeconfig`.
- The 1Password CLI and the service account of vault `homelab`, as in
  phase 1. The tasks read its token from
  `op://dotfiles/homelab-op-service-account/credential`.
- Network access to the lab subnet, and to `factory.talos.dev` and
  `quay.io`.

## Steps

### 1. The image schematic

`talos/schematic.yaml` is the Image Factory schematic: the stock Talos
image plus the QEMU guest agent. The factory names a schematic by the hash
of its content, so the file and the ID always belong together:

```
$ mise run talos:schematic
ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515
```

This is the ID of the disk image the VMs were created from (phase 1) and of
the installer image below.

### 2. The patches

`talosctl gen config` produces a complete default configuration. The
repository keeps only the differences, as patch files, which `talosctl`
merges in this order (D06):

| File | Applies to | Says |
|---|---|---|
| `talos/patches/cluster.yaml` | every node | the installer image; no flannel; from phase 6 a `UserVolumeConfig` for the data disk (Storage guide) |
| `talos/patches/controlplane.yaml` | control-plane nodes (all three) | no kube-proxy; the virtual IP; no control-plane taint |
| `talos/nodes/k8s-N.yaml` | one node | its hostname |

Since Talos v1.14 the configuration is a set of separate documents, one per
concern (`KubeProxyConfig`, `Layer2VIPConfig`, `HostnameConfig` and so on).
A patch names the document by `kind` and changes or deletes it.

`talos/patches/cluster.yaml`:

```yaml
apiVersion: v1alpha1
kind: UnattendedInstallConfig
installer:
  image: factory.talos.dev/nocloud-installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.14.6
---
apiVersion: v1alpha1
kind: KubeFlannelCNIConfig
$patch: delete
```

The installer image is what `talosctl upgrade` writes to disk. It has to be
the `nocloud` one: the Image Factory builds a separate installer per
platform (the `nocloud` and `metal` manifests have different digests), and
the platform decides where the node takes its address from. The Talos
defaults and the Proxmox guide use `metal-installer`; with it, a node would
lose its cloud-init address at the first upgrade (D31). Renovate reads the
version tag from this line.

Deleting `KubeFlannelCNIConfig` leaves the cluster without a network plugin
until Cilium is installed in step 7 (D08).

`talos/patches/controlplane.yaml`:

```yaml
apiVersion: v1alpha1
kind: KubeProxyConfig
enabled: false
---
apiVersion: v1alpha1
kind: Layer2VIPConfig
name: 10.0.6.10
link: eth0
---
apiVersion: v1alpha1
kind: KubeNodeConfig
labels:
  node.kubernetes.io/exclude-from-external-load-balancers:
    $patch: delete
taints:
  node-role.kubernetes.io/control-plane:
    $patch: delete
```

- Cilium takes over the service routing kube-proxy would do (D08).
- `Layer2VIPConfig` makes the control-plane nodes elect one holder of
  10.0.6.10 on `eth0`, the only network interface of each VM (D07). The
  election runs through etcd, so the address appears only after step 5.
- The default configuration taints control-plane nodes so that ordinary
  pods are not scheduled there, and labels them so that load balancers skip
  them. Every node here is also the worker (D01), so both go. They live in
  this file because only control-plane configurations contain them.

`talos/nodes/k8s-1.yaml`:

```yaml
apiVersion: v1alpha1
kind: HostnameConfig
auto:
  $patch: delete
hostname: k8s-1
```

The default `HostnameConfig` has `auto: stable`, which cannot be combined
with a fixed name, so the patch removes it. A hostname set here takes
precedence over the one cloud-init provides.

### 3. The cluster secrets

`talosctl gen secrets` creates the certificate authorities, keys and tokens
of a cluster. They are generated once and stored as one concealed field
`secrets` in item `talos` of vault `homelab` (D30):

```
$ mise run talos:secrets
stored item talos in vault homelab; the read-back matches
```

The task refuses to run when the item exists, because new secrets mean a
new cluster. The file never lands in the clone: every task that needs it
reads it into a private directory under `/run/user/<uid>` (memory, not
disk) and removes the directory when it ends.

### 4. Render and apply

`talos/talos.sh` holds the commands; the `talos:*` tasks call it and pass
on their arguments. Rendering one node's configuration is:

1. read the secrets from 1Password;
2. `talosctl gen config homelab https://10.0.6.10:6443 --with-secrets ...
   --kubernetes-version 1.36.6 --config-patch @talos/patches/cluster.yaml
   --config-patch-control-plane @talos/patches/controlplane.yaml`;
3. `talosctl machineconfig patch` with the node file.

`mise run talos:render k8s-1` prints the result. It contains every secret
of the cluster: pipe it, do not save it. A dry run against a node in
maintenance mode shows what would change. Against an empty node that is
the whole configuration, and it was not checked whether Talos hides the
keys in this diff, so do not paste it into a log or an issue:

```
$ mise run talos:apply k8s-1 --insecure --dry-run
...
+kind: Layer2VIPConfig
+name: 10.0.6.10
+link: eth0
```

Then the real apply, one node after the other:

```
$ mise run talos:apply k8s-1 --insecure
Applied configuration without a reboot
```

`--insecure` is needed only in maintenance mode, where the node has no
certificates yet. The node does not reboot and does not install: the
`nocloud` disk image is already an installed system (partitions `EFI`,
`STATE`, `META`, `EPHEMERAL` on `sda`), so Talos stores the configuration
in `STATE` and continues booting. Each node then waits in stage `booting`
for etcd.

Then write the administrator's client configuration. It is derived from the
secrets, so it can be recreated at any time:

```
$ mise run talos:config
wrote /home/agent/work/homelab/talosconfig
```

It lists all three nodes as endpoints and 10.0.6.11 as the default node.
The virtual IP is deliberately not an endpoint: it depends on etcd and
Kubernetes, and `talosctl` has to work when they do not.

### 5. Bootstrap etcd

Once, on one node:

```
$ mise run talos:bootstrap
$ talosctl -n 10.0.6.11 etcd members
NODE        ID                 HOSTNAME   PEER URLS                CLIENT URLS              LEARNER
10.0.6.11   0125afe55a537ee0   k8s-1      https://10.0.6.11:2380   https://10.0.6.11:2379   false
10.0.6.11   8b5b2801756e35da   k8s-3      https://10.0.6.13:2380   https://10.0.6.13:2379   false
10.0.6.11   d8433baf421b01c4   k8s-2      https://10.0.6.12:2380   https://10.0.6.12:2379   false
```

Within about 20 seconds all three members were there and the virtual IP
answered (`curl -sk https://10.0.6.10:6443/version` returns 401 until a
client certificate is presented, which proves the API server is behind
it).

### 6. Kubeconfig

```
$ mise run talos:kubeconfig
wrote /home/agent/work/homelab/kubeconfig
$ kubectl get nodes
NAME    STATUS     ROLES           AGE   VERSION
k8s-1   NotReady   <none>          2s    v1.36.6
k8s-2   NotReady   control-plane   27s   v1.36.6
k8s-3   NotReady   control-plane   21s   v1.36.6
```

The server in the file is `https://10.0.6.10:6443`. `NotReady` is expected:
there is no network plugin yet. The CoreDNS pods are `Pending` for the same
reason, and there is no kube-proxy pod.

### 7. Cilium

`kubernetes/apps/kube-system/cilium/app/` holds the chart reference
(`ocirepository.yaml`, chart 1.20.4 from `oci://quay.io/cilium/charts/cilium`)
and `values.yaml`. Phase 3 points Flux at the same two files, so Flux adopts
this installation instead of making a second one (D09). The values are:

- from the Talos guide "Deploying Cilium CNI": `ipam.mode: kubernetes`,
  `kubeProxyReplacement: true`, the API through KubePrism
  (`localhost:7445`, a load balancer Talos runs on every node, so Cilium
  does not depend on the virtual IP), the capability lists without
  `SYS_MODULE` and the cgroup settings that use the cgroup mount Talos
  already provides;
- from D26: `rollOutCiliumPods: true` and `operator.rollOutPods: true`, so a
  changed setting restarts the pods, and `hubble.enabled: false`. The chart
  defaults D26 was based on were confirmed in the chart's `values.yaml` at
  v1.20.4: both roll-out settings default to `false`, and Hubble is on by
  default with certificates generated by Helm (`hubble.tls.auto.method:
  helm`). With Hubble off no certificate is generated.

```
$ mise run bootstrap:cilium
Pulled: quay.io/cilium/charts/cilium:1.20.4
NAME: cilium
NAMESPACE: kube-system
STATUS: deployed
REVISION: 1
```

The task reads the URL and the tag from `ocirepository.yaml` and runs
`helm upgrade --install` with `--wait`, so it is also how Cilium is changed
until Flux exists.

## Check

Run on 2026-11-15 from the agent box.

```
$ kubectl get nodes -o wide
NAME    STATUS   ROLES           AGE    VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE          KERNEL-VERSION          CONTAINER-RUNTIME
k8s-1   Ready    control-plane   75s    v1.36.6   10.0.6.11     <none>        Talos (v1.14.6)   6.18.63-talos (amd64)   containerd://2.3.7
k8s-2   Ready    control-plane   100s   v1.36.6   10.0.6.12     <none>        Talos (v1.14.6)   6.18.63-talos (amd64)   containerd://2.3.7
k8s-3   Ready    control-plane   94s    v1.36.6   10.0.6.13     <none>        Talos (v1.14.6)   6.18.63-talos (amd64)   containerd://2.3.7

$ talosctl -n 10.0.6.11 etcd members
NODE        ID                 HOSTNAME   PEER URLS                CLIENT URLS              LEARNER
10.0.6.11   0125afe55a537ee0   k8s-1      https://10.0.6.11:2380   https://10.0.6.11:2379   false
10.0.6.11   8b5b2801756e35da   k8s-3      https://10.0.6.13:2380   https://10.0.6.13:2379   false
10.0.6.11   d8433baf421b01c4   k8s-2      https://10.0.6.12:2380   https://10.0.6.12:2379   false

$ cilium status --wait
    Cilium:             OK
    Operator:           OK
    Envoy DaemonSet:    OK
    Hubble Relay:       disabled
    ClusterMesh:        disabled
DaemonSet              cilium                   Desired: 3, Ready: 3/3, Available: 3/3
DaemonSet              cilium-envoy             Desired: 3, Ready: 3/3, Available: 3/3
Deployment             cilium-operator          Desired: 2, Ready: 2/2, Available: 2/2
Helm chart version:    1.20.4
```

`cilium status` does not print the kube-proxy replacement; the agent does:

```
$ kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status | grep KubeProxyReplacement
KubeProxyReplacement:    True   [eth0   10.0.6.12 fe80::be24:11ff:fe7a:2d40 (Direct Routing)]
$ kubectl get ds -n kube-system kube-proxy
Error from server (NotFound): daemonsets.apps "kube-proxy" not found
```

No taints, and ordinary pods run on every node:

```
$ kubectl get nodes -o jsonpath='{.items[*].spec.taints}'
                                          (empty)
$ kubectl create deployment gate --image=registry.k8s.io/pause:3.10 --replicas=3
deployment.apps/gate created
$ kubectl rollout status deployment/gate --timeout=2m
deployment "gate" successfully rolled out
$ kubectl get pods -l app=gate -o wide
gate-5464cbb545-4p7f9   Running   k8s-2
gate-5464cbb545-dmphw   Running   k8s-1
gate-5464cbb545-txzrx   Running   k8s-3
$ kubectl delete deployment gate
deployment.apps "gate" deleted from default namespace
```

`create deployment` printed a PodSecurity warning (`would violate
PodSecurity "restricted:latest"`). It is a warning, not a refusal: the
default namespace enforces nothing. Workload isolation is on
(`workloadIsolation: true` in the node's configuration, the default for new
v1.14 clusters) and does not keep pods off control-plane nodes.

### Virtual IP failover

The holder was k8s-1 (`talosctl get addresses` listed `10.0.6.10/32` only
there). The API was polled through the virtual IP once a second while the
holder rebooted:

```
$ ( while true; do printf '%s %s\n' "$(date +%T)" "$(curl -sk -m 2 -o /dev/null -w '%{http_code}' https://10.0.6.10:6443/version)"; sleep 1; done ) > vip.log &
$ talosctl -n 10.0.6.11 reboot
$ kubectl wait --for=condition=Ready nodes --all --timeout=10m
$ kill %1; awk '{print $2}' vip.log | sort | uniq -c
     64 401
```

No request failed. That is not a missed holder: k8s-1 had been up for 56
seconds afterwards, and k8s-2's log shows it took the address at the
moment of the reboot:

```
10.0.6.12: 2026-11-15T07:38:55.379Z INFO assigned address {"address": "10.0.6.10/32", "link": "eth0"}
10.0.6.12: 2026-11-15T07:38:55.387Z INFO sent gratuitous ARP {"address": "10.0.6.10", "link": "eth0"}
```

A clean reboot hands the address over before the node goes down. The gap
appears when the holder dies without warning. The same test with a hard
stop of the new holder through the Proxmox API (VM 202, `status/stop`,
started again 75 seconds later):

```
     30 000
     23 401
--- failed requests, first and last:
02:40:35 000
02:41:36 000
```

The API was unreachable for about 61 seconds (first to last failed
request), then k8s-3 served the address. Expect
the API through the virtual IP to be away for about a minute when its
holder crashes; `talosctl` keeps working, because it talks to the nodes
directly.

### Upgrade rehearsal

`talosctl upgrade` to the same version with the factory installer, on a
node that did not hold the virtual IP:

```
$ mise run talos:upgrade k8s-1 --progress plain
10.0.6.11: 2026/11/15 07:42:27 installation of v1.14.6 complete
10.0.6.11: upgrade completed
k8s-1: node cordoned
k8s-1: node uncordoned
```

The node was cordoned, rebooted (uptime 18 seconds afterwards) and came
back with hostname `k8s-1`, platform `nocloud`, address 10.0.6.11/24,
Talos v1.14.6, the extension `qemu-guest-agent` 11.1.1 and schematic
`ce4c9805...`. The `nocloud` installer keeps the node on its platform
(D31). The lines `error: reboot sequence completed` in the progress output
are how `talosctl` reports the end of a step, not errors.

## Day-two tasks

- **Change the configuration**: edit a patch, then for each node
  `mise run talos:apply k8s-N --dry-run` to read the difference, then
  without `--dry-run`. Talos decides whether the change needs a reboot.
- **Upgrade Talos** (D17): Renovate changes the tag in
  `talos/patches/cluster.yaml` and labels the pull request
  `upgrade-drill`. Merge it, apply the configuration to every node, then
  `mise run talos:upgrade k8s-N` one node at a time, waiting for
  `kubectl wait --for=condition=Ready nodes --all` between nodes. Upgrade
  the virtual IP holder last. `talosctl` is pinned in `mise.toml` and moves
  with the same drill.
- **Upgrade Kubernetes** (not tried yet): change `KUBERNETES_VERSION` in
  `mise.toml` (Renovate does), then `mise run talos:upgrade-k8s --dry-run`
  to read the plan, then `mise run talos:upgrade-k8s`. The task runs
  `talosctl upgrade-k8s --to $KUBERNETES_VERSION` through k8s-1; extra
  arguments pass through.
  Renovate proposes patch releases of the kubelet image; merging one only
  changes what `talos:render` produces, the cluster moves with
  `upgrade-k8s`. Renovate is held below 1.37 (`allowedVersions`) until a
  Cilium release lists it (D29).
- **Which Talos version is installed** (assumption, to be verified by the
  rebuild drill in phase 11, not a fact): the version pinned for the disk
  image in `infra/main.tf`, `infra/host/prepare.py` and `docs/host.md` is
  only used to boot new virtual machines into maintenance mode. The
  installed version is believed to come from the installer image in
  `talos/patches/cluster.yaml`, which `talos:apply` installs and
  `talos:upgrade` moves.
- **Change Cilium**: edit `values.yaml` or the tag, then
  `mise run bootstrap:cilium`. From phase 3 on, Flux does this after a
  merge, and `bootstrap:cilium` is only for a cluster without Flux.
- **Lost `talosconfig` or `kubeconfig`**: `mise run talos:config`, then
  `mise run talos:kubeconfig` (from k8s-1; name another node, e.g.
  `mise run talos:kubeconfig k8s-2`, when k8s-1 is down).
- **Rebuild the cluster from nothing** (not tried yet). The nodes and the
  stored secrets are independent, so either can be reset:
  1. Recreate the VMs. There is no destroy task; from `infra/`:

     ```sh
     export OP_SERVICE_ACCOUNT_TOKEN="$(op read op://dotfiles/homelab-op-service-account/credential)"
     op run --env-file op.env -- tofu init -input=false
     op run --env-file op.env -- tofu destroy
     ```

     then `mise run infra:apply`. They come back in maintenance mode.
  2. Keep the secrets in item `talos`, or, for a new identity, delete the
     item and run `mise run talos:secrets`.
  3. Steps 4 to 7 above: `talos:apply k8s-N --insecure` for each node,
     `talos:config`, `talos:bootstrap`, `talos:kubeconfig`,
     `bootstrap:cilium`.
  4. `mise run bootstrap:secrets`. It creates namespace `external-secrets`
     and applies the token External Secrets reads 1Password with; without
     it every Kustomization that needs a Secret from 1Password stays not
     Ready.
  5. `mise run bootstrap:flux`. It installs flux-operator, applies the
     FluxInstance and returns when Flux has adopted the two bootstrap
     releases (HelmReleases `cilium` and `flux-operator` are Ready). The
     other Kustomizations keep reconciling; watch them with
     `flux get kustomizations -A --watch`. Flux adopts the Cilium and
     flux-operator releases in place, and with the feature gate of D33 no pod should restart (shown for
     flux-operator on a test cluster; a full rebuild has not been run).

## When it goes wrong

- **`patch delete: path 'labels.node.kubernetes.io/exclude-from-external-load-balancers' in document 'v1alpha1/KubeNodeConfig': ... lookup failed`.**
  The taint and the label were first deleted in `cluster.yaml`.
  A delete of a missing key fails, and `--config-patch` is presumably also
  applied to the worker configuration, which does not have them (inferred
  from the error, not read in the source). They moved to
  `controlplane.yaml`.
- **`HostnameConfig: 'auto' and 'hostname' cannot be set at the same time`.**
  The node file first set only `hostname`. The default document carries
  `auto: stable`; the node file deletes it.
- **`error constructing client: failed to determine endpoints`.**
  `talosctl` was run from a shell without mise's environment, so it read
  `~/.talos/config`, which does not exist. Export `TALOSCONFIG` (see
  "Before you start") or run the command inside the clone through mise.

## Sources

- Talos v1.14 documentation (docs.siderolabs.com/talos/v1.14):
  [what's new](https://docs.siderolabs.com/talos/v1.14/getting-started/what's-new-in-talos.md)
  (the configuration split into documents),
  [patching](https://docs.siderolabs.com/talos/v1.14/configure-your-talos-cluster/system-configuration/patching.md)
  (`$patch: delete`, documents matched by kind),
  [Layer2VIPConfig](https://docs.siderolabs.com/talos/v1.14/reference/configuration/network/layer2vipconfig.md)
  and the [VIP guide](https://docs.siderolabs.com/talos/v1.14/networking/advanced/vip.md)
  (control planes only, not a `talosctl` endpoint),
  [HostnameConfig](https://docs.siderolabs.com/talos/v1.14/reference/configuration/network/hostnameconfig.md),
  [UnattendedInstallConfig](https://docs.siderolabs.com/talos/v1.14/reference/configuration/runtime/unattendedinstallconfig.md),
  [workloads on control plane](https://docs.siderolabs.com/talos/v1.14/deploy-and-manage-workloads/workloads-on-controlplane.md)
  (the taint in `KubeNodeConfig`),
  [SecurityProfileConfig](https://docs.siderolabs.com/talos/v1.14/reference/configuration/runtime/securityprofileconfig.md),
  the [support matrix](https://docs.siderolabs.com/talos/v1.14/getting-started/support-matrix)
  (Kubernetes 1.33 to 1.37) and the
  [CLI reference](https://docs.siderolabs.com/talos/v1.14/reference/cli.md)
  (`gen config`, `upgrade` flags).
- [Deploying Cilium CNI](https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium):
  the two documents for v1.14 and the Helm values, taken as they are.
- Cilium: the chart's
  [values.yaml at v1.20.4](https://raw.githubusercontent.com/cilium/cilium/v1.20.4/install/kubernetes/cilium/values.yaml)
  (defaults behind D26), the
  [compatibility page](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)
  (Kubernetes 1.33 to 1.36) and the
  [release page](https://github.com/cilium/cilium/releases) (1.20.4).
- [onedr0p/home-ops](https://github.com/onedr0p/home-ops): `talos/README.md`
  and `talos/mise.toml` for the three layers (cluster, role, node) merged by
  `talosctl machineconfig patch`, and the warning about partial `ca`
  patches; `bootstrap/helmfile/` for reading the chart version and values
  from the Flux files. Its template engine and its helmfile were not
  taken: one chart is installed with one `helm` command.
- `talosctl` v1.14.6 itself: `gen config` output for the default documents,
  the default Kubernetes version (1.37.1) and the `secrets.yaml` layout.
- factory.talos.dev: the installer manifests for the schematic, which
  showed that `nocloud-installer` and `metal-installer` are different
  images.
