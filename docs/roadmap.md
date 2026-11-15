# Roadmap

The phases in order. Exactly one is open. A phase is closed when every gate
command has passed on the real system with the work merged to `main`, the
output was shown to the owner, and its guide page is written. The
architect then tells the owner that the release pull request can be
merged.

At the start of every session, before phase work, the architect checks
Renovate (D23).

Each phase lists:

- **Needs from the owner**: things only the owner can do. Ask before
  starting, not halfway.
- **Read first**: research to do before writing anything. The design is
  decided; this is about current syntax, versions and file shapes.
- **Build**: the work.
- **Decide here**: choices deliberately left to this phase, with the
  criteria. Record the outcome in [Decisions](decisions.md).
- **Prove here**: assumptions in the design that only this phase can test.
  If one fails, stop and tell the owner; do not work around it.
- **Gate**: the commands whose output closes the phase.
- **Guide**: the page to write (see [Standards](standards.md)).

| Phase | State |
|---|---|
| Host preparation | done 2026-11-15, see [Host](host.md) |
| 0 Repository foundation | open |
| 1 Nodes | not started |
| 2 Cluster | not started |
| 3 Flux | not started |
| 4 Secrets | not started |
| 5 Ingress | not started |
| 6 Storage | not started |
| 7 First database | not started |
| 8 First application | not started |
| 9 Monitoring | not started |

## Phase 0: repository foundation

The repository checks every change, publishes its documentation, cuts
releases and receives update pull requests. The model is the owner's
`obenhub` repository (`/home/agent/work/obenhub` on the box); copy its
mechanics and leave what is specific to that project.

**Needs from the owner**
- When the release pull request exists: approve its workflow run in the
  Actions tab so that the required checks run on it (obenhub works the same
  way). Commit and push permission is granted (see `AGENTS.md`), and the
  owner has installed the Renovate app.

**Read first**
- In obenhub: `AGENTS.md` (the change flow), `CONTRIBUTING.md` (ruleset and
  release notes), `.github/workflows/` (`ci.yml`, `pr-title.yml`,
  `release-please.yml`, `docs.yml`), `release-please-config.json`,
  `renovate.json`, `.github/pull_request_template.md`,
  `scripts/check-commits.sh`.
- Zensical: "Publish your site" at zensical.org, for the Pages workflow.
- Renovate: the `terraform`, `flux`, `github-actions` and `mise` managers,
  and how `home-operations/renovate-presets` tracks Talos versions
  (`apps/talosFactory.json5`).
- GitHub: repository rulesets API, to create the `main` ruleset from the
  command line.
- release-please: which commit types open a release pull request, and how
  obenhub gets the required checks to run on that pull request
  (`CONTRIBUTING.md` there: its workflows need an approval in the Actions
  tab because the pull request is opened with the workflow token).

**Build**
- `mise.toml`: pinned versions of `opentofu`, `talosctl`, `kubectl`, `helm`,
  `flux2`, `cilium-cli`, `uv`; tasks `docs:serve`, `docs:build` and
  `check`. `check` runs what can be validated without a cluster; in this
  phase that is the documentation build, `python3 -m py_compile` and
  `ruff check` on `infra/host/prepare.py`. Later
  phases add `tofu validate`, `tofu fmt -check` and a Kubernetes manifest
  build.
- Workflows, every action pinned by full commit SHA, `permissions: {}` at
  the top: `ci.yml` (job `check`), `pr-title.yml` (job `semantic-title`),
  `release-please.yml`, `docs.yml` (build on pull requests, deploy to Pages
  on `main`).
- release-please in `simple` mode, tags `vX.Y.Z`, starting at 0.1.0.
- `.renovaterc.json5`: recommended presets, semantic commits, dependency
  dashboard, pinned action digests; schedule before 6am on Monday
  (Europe/Istanbul); minimum release age 3 days; groups for GitHub Actions
  and for mise tools; OpenTofu providers resolved from
  `registry.opentofu.org`. Renovate opens an onboarding pull request
  once the repository has a commit; put this configuration into that pull
  request's branch and merge it, or, if the configuration reached `main`
  another way, close the onboarding pull request.
- Pull request template: summary, how it was verified, checklist.
- GitHub settings: squash merge only, delete branches after merge, Pages
  from the workflow, GitHub Actions allowed to create pull requests (for
  release-please), and a ruleset on `main` that requires a pull request
  (no approvals), the checks `check` and `semantic-title`, linear history,
  and blocks force pushes and deletion.

**Gate**
```
mise install && mise run check                              # exits 0
curl -sI https://msavdert.github.io/homelab/ | head -1      # HTTP/2 200
opgh api repos/msavdert/homelab/rules/branches/main --jq '.[].type' | sort
```
The last command lists at least `deletion`, `non_fast_forward`,
`pull_request`, `required_linear_history` and `required_status_checks`,
and the ruleset's own record (`opgh api repos/msavdert/homelab/rulesets`
for its ID, then `.../rulesets/<id>`) has an empty `bypass_actors` list.
To see `semantic-title` fail, open a pull request titled `bad title` from
a throwaway branch, look at the check, and close it.
A pull request with a title that is not a Conventional Commit fails
`semantic-title`. A release pull request opened by release-please exists
(it appears only after a `feat` or `fix` commit reaches `main`; the first
commit of the repository is a `feat`), and its required checks have run.
The Dependency Dashboard issue exists and lists no configuration error.

**Guide**: `docs/guide/00-repository.md`: how a change travels from branch
to release, written for the owner.

## Phase 1: nodes

Three virtual machines exist and run Talos in maintenance mode.

**Needs from the owner**: nothing. The token `homelab@pve!tofu` exists
and holds exactly the four permission paths in [Host](host.md) (checked
2026-11-15). The state passphrase is in `op://homelab/tofu-state/password`.

**State backend** (D24): the `s3` backend on bucket `homelab`, key
`tofu/homelab.tfstate`, endpoint, region and keys from
`op://homelab/object-storage` (`endpoint`, `region`, `access-key`,
`secret-key`), path-style addressing, `use_lockfile = true`. All three
items OpenTofu needs (`proxmox-tofu`, `tofu-state`, `object-storage`) are
in vault `homelab`, so the tasks run one `op run` with that vault's token. The bucket was
tested with aws-cli: conditional writes are honoured, which is what the
lock file needs.

**Read first**
- bpg/proxmox provider documentation for `proxmox_virtual_environment_vm`:
  the `disk` block with `import_from`, the `initialization` block
  (`ip_config`, `dns`), `efi_disk`, `agent`, `pool_id`. The VM that the host
  test created through the raw API is the reference for the values
  ([Architecture](architecture.md), "Nodes").
- OpenTofu: state encryption (`pbkdf2` key provider, `aes_gcm` method,
  `TF_ENCRYPTION`), the `s3` backend options for non-AWS stores.
- One public repository that creates Talos VMs with this provider, for the
  resource shape only.

**Build**
- `infra/`: provider and backend configuration, one `for_each` over a map of
  the three nodes. No modules, no variables file for a second environment.
- mise tasks `infra:plan` and `infra:apply` that inject credentials with
  `op run`, and `infra:pool`, which lists the members of pool `homelab`
  through the API with the `tofu` token.

**Prove here**
- State locking with `use_lockfile` through OpenTofu itself: start a second
  `tofu plan` while one holds the lock and see it refused. The raw
  conditional write was tested; OpenTofu's use of it was not.
- Which checksum settings the backend needs on this store (the
  `skip_s3_checksum` option and the `AWS_REQUEST_CHECKSUM_CALCULATION`
  variable). A multi-object delete with the default CRC32 checksum was
  refused in the bucket test.
- That nothing readable is stored: download the state object and confirm it
  is not plain JSON.
- A fresh clone can run `infra:plan` and reports no changes.

**Gate**
```
for ip in 10.0.6.11 10.0.6.12 10.0.6.13; do talosctl get disks --insecure --nodes $ip; done
```
Each lists `sda` (about 21 GB) and `sdb` (about 107 GB).
```
git clone https://github.com/msavdert/homelab /tmp/fresh && cd /tmp/fresh && mise run infra:plan   # "No changes"
mise run infra:pool        # a task that lists the pool members with the tofu token
```
The pool lists exactly the VMs 201, 202 and 203 and the storage
`local-zfs`.

**Guide**: `docs/guide/01-nodes.md`.

## Phase 2: cluster

Kubernetes runs on the three nodes with Cilium.

**Needs from the owner**: nothing. The `homelab` vault service account
can create items (tested 2026-11-15 by creating `tofu-state`).

**Read first**
- Talos v1.14 documentation: the multi-document machine config
  (`KubeFlannelCNIConfig`, `KubeProxyConfig`, `KubeNodeConfig`,
  `Layer2VIPConfig`, `UnattendedInstallConfig`, `UserVolumeConfig` is for
  phase 6), "Deploying Cilium CNI", "Workloads on control plane", the
  `nocloud` platform page, and the Image Factory page for the installer
  image name of a `nocloud` schematic.
- onedr0p/home-ops: `talos/README.md`, `talos/cluster.yaml.j2`,
  `bootstrap/README.md`, `bootstrap/helmfile/`. Take the patch structure
  and the way bootstrap reads the chart version from the Flux files. Leave
  the template engine.
- Cilium documentation and the chart's `values.yaml` for the current
  release: the Talos-specific values, and the defaults of
  `rollOutCiliumPods`, `operator.rollOutPods` and `hubble.*` that D26 is
  based on. If a default differs from what D26 assumes, keep the intent of
  D26 (a changed setting restarts the agents; nothing regenerates on every
  reconciliation) and note the difference in the decision record.

**Build**
- `talos/`: `schematic.yaml`, a cluster patch, a control-plane patch, one
  small patch per node; mise tasks to render, apply, bootstrap, fetch
  kubeconfig, and to upgrade one node. The per-node patch contains only the
  hostname (`k8s-1` to `k8s-3`), set explicitly so that it does not depend
  on what the `nocloud` platform or Talos's automatic hostname provides.
  The address, gateway and resolvers come from cloud-init. Everything else
  is in the shared patches.
- Cilium values as fixed in D08 and D26.
- Cluster secrets generated once with `talosctl gen secrets`, stored in
  item `talos`, deleted from disk.
- `kubernetes/apps/kube-system/cilium/app/`: the chart reference and the
  values file. They are created here because this phase installs Cilium
  from them with Helm; phase 3 adds the Flux objects that point at the same
  files. This is the only part of `kubernetes/` that phase 2 creates.

**Decide here**
- Whether `talosconfig` and `kubeconfig` are regenerated on demand from
  1Password or kept on disk outside the repository. Prefer regeneration; it
  survives a box rebuild.

**Prove here**
- The `nocloud` disk image accepts a machine config and keeps its static
  address and hostname afterwards.
- The virtual IP comes up after bootstrap and moves when its holder
  reboots.
- Talos v1.14 `workloadIsolation` does not prevent ordinary pods on
  control-plane nodes.
- `talosctl upgrade` to the same version with the factory installer image
  works on one node (rehearsal of the upgrade path).

**Gate**
```
kubectl get nodes -o wide                    # three nodes Ready
talosctl -n 10.0.6.11 etcd members           # three members
cilium status --wait                         # OK, kube-proxy replacement on
kubectl get nodes -o jsonpath='{.items[*].spec.taints}'      # empty: no control-plane taint
kubectl create deployment gate --image=registry.k8s.io/pause:3.10 --replicas=3
kubectl rollout status deployment/gate --timeout=2m          # ordinary pods run on these nodes
kubectl delete deployment gate
```
Virtual IP failover, observed while it happens. Find the node that holds
10.0.6.10 (`talosctl get addresses` on each node), then:
```
( while true; do printf '%s %s\n' "$(date +%T)" "$(curl -sk -m 2 -o /dev/null -w '%{http_code}' https://10.0.6.10:6443/version)"; sleep 1; done ) > vip.log &
talosctl -n <holder> reboot
kubectl wait --for=condition=Ready nodes --all --timeout=10m
kill %1; awk '{print $2}' vip.log | sort | uniq -c
```
The log shows answers before and after the reboot and a gap of failed
requests (code 000) shorter than 60 seconds in between. A log without any
gap means the reboot did not hit the holder; repeat with the right node.

**Guide**: `docs/guide/02-cluster.md`, including how to rebuild the cluster
from nothing.

## Phase 3: Flux

The cluster reconciles from this repository.

**Read first**
- Flux Operator documentation: `FluxInstance`, sync from a public Git
  repository.
- onedr0p/home-ops and buroa/home-ops: `kubernetes/` tree, one application
  directory in full (`ks.yaml`, `app/kustomization.yaml`,
  `helmrelease.yaml`, `ocirepository.yaml`). Take the layout
  `kubernetes/apps/<namespace>/<app>/`. Leave components the lab does not
  have.
- Renovate `flux` manager: which file patterns must be configured.

**Build**
- `kubernetes/`: the Flux entry point and Cilium as the first managed
  application, using the same values as bootstrap.
- Bootstrap tasks for flux-operator and the FluxInstance.

**Prove here**
- Flux takes over the existing Cilium release without restarting the agent
  pods.

**Gate**
```
flux get kustomizations -A        # all Ready
flux get helmreleases -A          # cilium Ready
```
Then merge a pull request that changes one Cilium value that is visible in
the cluster (for example a pod annotation), run nothing by hand, and within
the sync interval:
```
flux get kustomizations -A        # revision equals `git rev-parse origin/main`
kubectl -n kube-system get ds cilium -o jsonpath='{.spec.template.metadata.annotations}'   # shows the new value
```

**Guide**: `docs/guide/03-flux.md`, including "how to add an application".

## Phase 4: secrets

A secret from 1Password appears in the cluster.

**Needs from the owner** (D25)
- A 1Password vault `homelab-cluster` and a service account that can only
  read it.
- That account's token in vault `homelab`, item `eso-service-account`,
  field `credential`.
- A copy of item `cloudflare-dns` in vault `homelab-cluster`.

The read-write account of vault `homelab` is never given to the cluster.

**Read first**
- External Secrets Operator: the 1Password SDK provider page.
- buroa/home-ops: `kubernetes/apps/external-secrets/external-secrets/stores/onepassword.yaml`
  and `bootstrap/kustomize/apps/external-secrets/secret.yaml`.

**Build**
- External Secrets Operator through Flux, one `ClusterSecretStore`.
- One `ExternalSecret` named `eso-gate` in namespace `external-secrets`
  that copies the `credential` field of `cloudflare-dns`. It exists to
  prove the path and is removed in phase 5, when cert-manager gets the
  real one.
- A bootstrap task that creates the `external-secrets` namespace if it does
  not exist and applies the token from `eso-service-account` as a Secret
  with `op inject`. It must work on a cluster where Flux has not run yet,
  because a rebuild runs it before Flux.

**Gate**
```
kubectl get clustersecretstore                       # Ready
kubectl -n external-secrets get externalsecret eso-gate               # SecretSynced
kubectl -n external-secrets get secret eso-gate -o jsonpath='{.data.credential}' | base64 -d | sha256sum
OP_SERVICE_ACCOUNT_TOKEN="$(op read op://dotfiles/homelab-op-service-account/credential)" op read op://homelab/cloudflare-dns/credential | tr -d '\n' | sha256sum
```
The two hashes are equal. The value itself is never printed.

**Guide**: `docs/guide/04-secrets.md`, including "how to add a secret".

## Phase 5: ingress

One test service answers over the tailnet with a valid certificate.

**Needs from the owner**
- The owner's own device for the positive test. The tailnet side is done:
  the subnet router advertises 10.0.6.0/24 and the policy grants members
  access to it (checked 2026-11-15, see `docs/handoff.md`).

**Read first**
- Cilium documentation for the current release: "LoadBalancer IP Address
  Management (LB IPAM)" and "L2 Announcements": the Helm values to enable
  them, `CiliumLoadBalancerIPPool`, `CiliumL2AnnouncementPolicy`, and the
  note on Kubernetes client rate limits.
- Envoy Gateway: installation with Helm, `GatewayClass`, `EnvoyProxy`
  settings for the proxy Service (a fixed load-balancer address), TLS with
  cert-manager.
- cert-manager: Cloudflare DNS-01 issuer, Gateway API support
  (`enableGatewayAPI`), and that the Gateway API CRDs must exist first.
- How the reference repositories install the Gateway API CRDs and Envoy
  Gateway (`kubernetes/apps/network/envoy-gateway/` in onedr0p/home-ops).

**Build**
- Cilium: enable LB IPAM and layer-2 announcements; a pool 10.0.6.20 to
  10.0.6.29; an announcement policy for the node interface.
- cert-manager with a Let's Encrypt `ClusterIssuer` using the token from
  item `cloudflare-dns`, delivered by External Secrets.
- Envoy Gateway, one `Gateway` at 10.0.6.20 with the wildcard certificate
  for `*.lab.savdert.com`, an echo service with an `HTTPRoute`.
- The DNS record `*.lab.savdert.com`, type A, value 10.0.6.20, not proxied.

The DNS record is created by a small idempotent script behind the mise task
`dns:apply`, in the style of `infra/host/prepare.py`, using the Cloudflare
API with the token in `cloudflare-dns`. It is one static record: no
controller in the cluster and no second OpenTofu root.

**Decide here**
- Who installs the Gateway API CRDs: the Envoy Gateway chart or a separate
  Flux Kustomization. Criterion: the CRDs must exist before cert-manager
  starts with Gateway API support and before any `Gateway` is applied, and
  a Renovate update of Envoy Gateway must not silently change the CRD
  version cert-manager depends on. Do what onedr0p/home-ops does unless it
  fails that criterion, and express the order with `dependsOn`.

**Prove here**
- Cilium answers ARP for 10.0.6.20 on the Proxmox VNet bridge and the
  address moves when the announcing node goes away.
- A public DNS record with a private address resolves on the owner's
  device. Some home routers drop such answers (DNS rebinding protection).
  If that happens, the fallback is a global nameserver override in the
  tailnet's DNS settings (for example 1.1.1.1), which bypasses the router;
  record which was needed.
- The certificate is issued with DNS-01 by the token in `cloudflare-dns`.
  The token was checked on 2026-11-15: it sees only zone `savdert.com` and
  can create and delete a record.

**Gate**
```
# from the agent box (it reaches the subnet through the host):
curl -sS -m 10 https://echo.lab.savdert.com/ -o /dev/null -w '%{http_code} %{ssl_verify_result}\n'    # 200 0
# from the owner's device on the tailnet: the same command, same result
# from the owner's device with Tailscale switched off:
curl -sS --connect-timeout 5 https://echo.lab.savdert.com/; echo "exit $?"                           # exit 7 or 28 (no route), not 6 (DNS)
```
Address failover, observed while it happens, from the agent box:
```
kubectl -n kube-system get lease | grep l2announce          # shows which node announces 10.0.6.20
( while true; do printf '%s %s\n' "$(date +%T)" "$(curl -s -m 2 -o /dev/null -w '%{http_code}' https://echo.lab.savdert.com/)"; sleep 1; done ) > lb.log &
talosctl -n <that node> reboot
kubectl wait --for=condition=Ready nodes --all --timeout=10m
kill %1; awk '{print $2}' lb.log | sort | uniq -c
```
The log shows 200 before and after and a gap shorter than 60 seconds.

**Guide**: `docs/guide/05-ingress.md`, including "how to expose a service"
and how the tailnet reaches the lab.

## Phase 6: storage

A volume keeps its data across a node reboot.

**Read first**
- Sidero "Local storage" guide and the Talos `UserVolumeConfig` reference.
- local-path-provisioner: `nodePathMap` and the Helm chart or manifest
  source the reference repositories use.

**Build**
- `UserVolumeConfig` on `/dev/sdb` for all nodes; local-path-provisioner
  through Flux with its path set to the volume's mount point; one
  StorageClass, set as default.
- The provisioner's namespace is labelled
  `pod-security.kubernetes.io/enforce: privileged`: its helper pods mount
  host paths, which the default pod security level refuses (Sidero local
  storage guide).

**Gate**
```
kubectl apply -f <a test pod with a 1Gi PVC that writes a timestamp to /data/proof>
kubectl exec storage-test -- cat /data/proof                 # note the value and the node
kubectl exec storage-test -- df -h /data                     # about 100G: the data disk, not the 20G system disk
talosctl -n <that node> get mountstatus                      # lists the user volume on /dev/sdb
talosctl -n <that node> reboot
kubectl wait --for=condition=Ready pod/storage-test --timeout=10m
kubectl exec storage-test -- cat /data/proof                 # same value, same node
kubectl delete -f <the test manifest>
kubectl get pv                                               # the test volume is gone
```
The test manifest is applied by hand and is not committed.

**Guide**: `docs/guide/06-storage.md`, stating plainly that volumes are
bound to a node and what that means during a drain.

## Phase 7: first database

A PostgreSQL cluster runs, is backed up and is restored to a point in time.

**Needs from the owner**
- An access key that can reach only bucket `homelab`, stored in vault
  `homelab-cluster` as item `object-storage` (`access-key`, `secret-key`,
  `endpoint`, `region`, `bucket`). The key the workstation uses reaches
  every bucket of the account and is not given to the cluster.

**Read first**
- CloudNativePG documentation for the current release: installation,
  the Barman Cloud Plugin (`ObjectStore`, plugin configuration on the
  `Cluster`), recovery and `recoveryTarget`.
- The plugin's "Object stores" page: the checksum environment variables for
  S3-compatible stores (`AWS_REQUEST_CHECKSUM_CALCULATION`,
  `AWS_RESPONSE_CHECKSUM_VALIDATION`).

**Build**
- The operator and plugin through Flux; the cluster with the parameters
  fixed in D27; scheduled base backup and WAL archiving to the bucket.

**Prove here**
- The bucket accepts the plugin's retention deletes. In the bucket tests a
  multi-object delete was refused both with the default checksum and with
  `when_required`, and accepted only with CRC32C (D24). Whether the
  plugin's S3 client is affected depends on its version. Test it early in
  the phase with a retention of one day. If deletes fail, apply the
  fallback fixed in D24 and say so in the guide.

**Gate**
1. `kubectl cnpg status <cluster>`: three instances, continuous archiving
   working, a completed base backup.
2. With `psql` on the primary: insert a row, note `now()`, insert a second
   row. Force a WAL switch (`select pg_switch_wal()`).
3. Create a second `Cluster` with `bootstrap.recovery` from the object
   store and `recoveryTarget.targetTime` set between the two inserts.
4. `select` on the restored cluster returns the first row and not the
   second.
5. `kubectl drain` the node of the primary: `kubectl cnpg status` shows a
   replica promoted, and a `psql` through the `-rw` Service works again
   within a minute. `kubectl uncordon` the node; `kubectl cnpg status`
   shows three healthy instances again.
6. Retention: an expired base backup and its WAL are gone from the bucket,
   by the plugin or by the fallback in D24.

**Guide**: `docs/guide/07-database.md`, written as a drill someone can
repeat.

## Phase 8: first application

The owner names the application when this phase opens. From here the
database track (more drills: failover, major upgrade, replica cluster) and
the application track alternate; each addition is its own small phase with
a gate.

**Gate**, written as commands with the application's name when the phase
opens (opening a phase includes writing its gate): the application answers at `https://<name>.lab.savdert.com` from the
owner's device; its data is still there after its pod is deleted and
recreated; if it uses PostgreSQL, the database is a CloudNativePG cluster.

**Decide here**
- Backup of application volumes: none by default (D16). Revisit only if the
  owner names data worth keeping; candidates then are VolSync with restic
  and Kopiur, both working at file level because the storage has no
  snapshots.

## Phase 9: monitoring

One tool, last.

**Decide here**
- VictoriaMetrics (`victoria-metrics-k8s-stack`) or
  `kube-prometheus-stack`. Criteria: memory footprint on 8 GiB nodes, a
  CloudNativePG dashboard that works out of the box, number of components.
  Read both charts' current documentation and what the reference
  repositories run before choosing.

**Gate**, written as commands once the tool is chosen: a dashboard at `https://<name>.lab.savdert.com` shows CPU and
memory per node and the replication state of the PostgreSQL cluster from
phase 7, and the tool's own pods use less than 2 GiB of memory in total
(`kubectl top pods -n <namespace>`).
