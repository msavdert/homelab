# Roadmap

The phases in order. At most one is open; between phases, maintenance
follows AGENTS.md, "Between phases". A phase is closed when every gate
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
| 0 Repository foundation | done 2026-11-15, see [Repository](guide/00-repository.md) |
| 1 Nodes | done 2026-11-15, see [Nodes](guide/01-nodes.md) |
| 2 Cluster | done 2026-11-15, see [Cluster](guide/02-cluster.md) |
| 3 Flux | done 2026-11-15, see [Flux](guide/03-flux.md) |
| 4 Secrets | done 2026-11-15, see [Secrets](guide/04-secrets.md) |
| 5 Ingress | done 2026-11-15, see [Ingress](guide/05-ingress.md) |
| 6 Storage | done 2026-11-16, see [Storage](guide/06-storage.md) |
| 7 First database | done 2026-11-16 (step 6b follow-up open, D37), see [Database](guide/07-database.md) |
| 8 First application: Keycloak | done 2026-11-17, see [Keycloak](guide/08-keycloak.md) |
| 9 Start page: Homepage | done 2026-11-17, see [Homepage](guide/09-homepage.md) |
| 10 Monitoring | done 2026-11-17, see [Monitoring](guide/10-monitoring.md) |
| 11 Rebuild and restore drill | done 2026-11-17, see [Rebuild](guide/11-rebuild.md) |
| 12 Alert delivery and dead man's switch | open 2026-11-19 |
| 13 Backup and database alerts | planned (D46), not open |
| 14 Proxmox host and ZFS | planned (D46), not open |
| 15 Logs | planned (D46), not open |
| 16 Control plane metrics | planned (D46), not open |

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
Each lists `sda` (22 GB: talosctl shows 20 GiB in decimal units, rounded) and `sdb` (107 GB).
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
requests (code 000) shorter than 60 seconds in between. A clean reboot
hands the address over before the node goes down, so the gap can be
zero; check that the holder rebooted (its uptime) and that another node
holds the address afterwards. A hard stop of the holder leaves a gap of
about a minute (measured 2026-11-15, [Cluster](guide/02-cluster.md)).

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
  `when_required`, and accepted only with CRC32C (D24). By its source, the
  plugin's sidecar has no way to use CRC32C (D36). Test it early in the
  phase: take a second base backup with a manual `Backup`, delete the older
  one with `barman-cloud-backup-delete` inside the sidecar and check the
  bucket. If deletes fail, apply the
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
6. Retention: an expired base backup and its WAL are gone from the bucket.
   Split in two by D37:
   - 6a, closes the gate: `barman-cloud-backup-delete` with a retention
     policy (`REDUNDANCY 2`), run from the sidecar image against the
     bucket, removes the older backups and the WAL before the oldest kept
     backup; a direct listing of the bucket confirms it.
   - 6b, a follow-up that does not hold the next phase: the plugin's own
     retention run removes a backup that expired under `1d`, or the
     fallback in D24 is applied. Retention then goes back to `7d`.

**Guide**: `docs/guide/07-database.md`, written as a drill someone can
repeat.

## Phase 8: first application: Keycloak

Keycloak answers over the tailnet and keeps its data in its own
CloudNativePG cluster, which is backed up.

The owner named Keycloak on 2026-11-16 (D38). From here the database track
(more drills: failover, major upgrade, replica cluster) and the
application track alternate; each addition is its own small phase with a
gate.

**Needs from the owner**
- Nothing new. The architect creates item `keycloak` in vault
  `homelab-cluster` (`username`, `password`, the password generated by
  1Password) with the `homelab` service account; the owner approved this
  on 2026-11-16.

**Read first**
- Keycloak Operator documentation for the pinned release: installation
  without OLM, the `Keycloak` resource (`db`, `http`, `hostname`, `proxy`,
  `ingress`, `bootstrapAdmin`, `resources`) and the upgrade order.
- The operator's CRD at that tag, for the field names the documentation
  shows only in part (`http.httpEnabled`, the keys of the database
  Secrets).
- Whether the operator and Keycloak pods meet the `restricted` pod
  security level, from their manifests.
- How Renovate updates a Flux `GitRepository` tag, so the operator version
  does not go stale.
- CloudNativePG: a `Cluster` and `ObjectStore` in an application
  namespace, with the `object-storage` item delivered there.

**Build**
- Namespace `keycloak`, pod security level `restricted`.
- The Keycloak Operator from `keycloak-k8s-resources` at the release tag,
  its CRDs excluded from pruning (D38).
- Cluster `keycloak-db` with the defaults of D39, backups to
  `cnpg/keycloak-db/`.
- An `ExternalSecret` from item `keycloak` for the bootstrap admin, and a
  `Keycloak` resource: one instance, the database from `keycloak-db-app`,
  hostname `keycloak.lab.savdert.com`, `X-Forwarded-*` headers, plain HTTP
  behind Envoy, the operator's own Ingress off.
- An `HTTPRoute` for `keycloak.lab.savdert.com` to the operator's Service
  on port 8080.

**Decide here**
- Memory request and limit for Keycloak, from its usage after start. The
  operator's default is 1700 MiB requested and a 2 GiB limit; the sizing
  guide gives 1250 MB as the base per pod. Decided: D40.
- Backup of application volumes: none needed. Keycloak keeps its state in
  `keycloak-db`, which D15 backs up; D16 stands.

**Prove here**
- Behind Envoy, Keycloak builds its URLs from the public name: the issuer
  in the discovery document is `https://keycloak.lab.savdert.com/realms/master`.

**Gate**
1. `kubectl cnpg status keycloak-db -n keycloak`: two instances on
   different nodes, continuous archiving working, a completed base backup;
   a listing of `cnpg/keycloak-db/` in the bucket shows it.
2. From the owner's device: `curl -s
   https://keycloak.lab.savdert.com/realms/master/.well-known/openid-configuration
   | jq -r .issuer` prints `https://keycloak.lab.savdert.com/realms/master`,
   and the admin console accepts the login from item `keycloak`.
3. With `kcadm.sh` in the Keycloak pod: create realm `gate` and user
   `gate-user` in it. Delete the Keycloak pod; once the new pod is ready,
   `kcadm.sh get realms/gate` and `kcadm.sh get users -r gate -q
   username=gate-user` return both.
4. `kubectl get ns keycloak --show-labels` shows
   `pod-security.kubernetes.io/enforce=restricted`, and the operator and
   Keycloak pods run in it.

**Guide**: `docs/guide/08-keycloak.md`.

## Phase 9: start page: Homepage

A start page for the lab's applications at `home.lab.savdert.com`, which
only a user of Keycloak realm `lab` can open.

The owner chose this before monitoring on 2026-11-17 and settled the login
the same day (D41).

**Needs from the owner**
- Nothing new. The architect creates items `homepage` and
  `keycloak-lab-user` in vault `homelab-cluster` with the `homelab`
  service account; the owner approved this on 2026-11-17.

**Read first**
- Homepage installation for Kubernetes and the authentication section of
  the installation page, for the pinned release: the manifests, the
  ClusterRole, `HOMEPAGE_ALLOWED_HOSTS` and the `HOMEPAGE_AUTH_*` and
  `HOMEPAGE_OIDC_*` variables. Done 2026-11-17 for v2.8.0.
- Homepage's Kubernetes configuration: `gateway: true` and the
  `gethomepage.dev/*` annotations on an `HTTPRoute`.
- Keycloak Operator `KeycloakRealmImport` at 26.8.2: the Job it runs,
  `placeholders`, and what happens when the realm exists. Done 2026-11-17.
- Keycloak's `RealmRepresentation`, for the client and user fields used in
  the import.

**Build**
- Item `homepage` (`oidc-client-secret`, `auth-secret`) and item
  `keycloak-lab-user` (`username` `owner`, `password`) in vault
  `homelab-cluster`, values generated by 1Password.
- In `keycloak`: an `ExternalSecret` for the client secret and the user,
  and a `KeycloakRealmImport` that creates realm `lab` with the
  confidential client `homepage` (standard flow, redirect URI
  `https://home.lab.savdert.com/api/auth/callback/homepage-oidc`) and user
  `owner`, the secrets passed as placeholders.
- Namespace `homepage`, pod security level `restricted`, with Homepage
  from plain manifests in the shape of the upstream page: ServiceAccount,
  read-only ClusterRole, ConfigMap, Deployment, Service, `HTTPRoute`. The
  image is pinned and Renovate's `kubernetes` manager updates it. Login by
  Homepage's own OIDC against
  `https://keycloak.lab.savdert.com/realms/lab`; the secrets from an
  `ExternalSecret` on item `homepage`.
- Services found from `HTTPRoute` annotations (`gateway: true`); the
  Keycloak route gets the first ones.

**Decide here**
- Whether Homepage runs with a read-only root file system, from a test.
  Record the outcome with D41. Decided: yes, with every skeleton file
  mounted (D41).

**Prove here**
- The Homepage pod reaches the issuer at `keycloak.lab.savdert.com` from
  inside the cluster, through the Gateway, and trusts its certificate.
- The realm import Job runs under pod security level `restricted`
  (it copies the Keycloak pod template, so it should).

**Gate**
1. Without a session the page is closed:
   `curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n'
   https://home.lab.savdert.com/` does not return the dashboard; it
   redirects to the sign-in page.
2. `curl -s
   https://keycloak.lab.savdert.com/realms/lab/.well-known/openid-configuration
   | jq -r .issuer` prints `https://keycloak.lab.savdert.com/realms/lab`.
3. From the owner's device: the sign-in goes to Keycloak realm `lab`, the
   login from item `keycloak-lab-user` is accepted, and the page shows a
   Keycloak entry found from its `HTTPRoute`, with its status up.
4. Delete the Homepage pod; once the new pod is ready, step 3 works again
   without any manual step.
5. `kubectl get ns homepage --show-labels` shows
   `pod-security.kubernetes.io/enforce=restricted`, and the Homepage pod
   runs in it.

**Guide**: `docs/guide/09-homepage.md`.

## Phase 10: monitoring

Metrics for the nodes and the databases, and a Grafana at
`grafana.lab.savdert.com` that only a user of Keycloak realm `lab` can open.

The owner left the choice of tool to the architect on 2026-11-17. Settled:
`victoria-metrics-k8s-stack`, Prometheus-format scraping, OTLP later (D42);
Grafana's own OIDC against realm `lab` (D43).

**Needs from the owner**
- Nothing new. The architect creates item `grafana` (`admin-password`,
  `oidc-client-secret`, values generated by 1Password) in vault
  `homelab-cluster` with the `homelab` service account, and the Keycloak
  client with `kcadm.sh`, under the delegation of 2026-11-17.

**Read first**
- `victoria-metrics-k8s-stack` values for the pinned version: VMSingle
  retention and storage, VMAgent, `operator.disable_prometheus_converter`,
  the `kube*` scrape switches, alerting (vmalert, Alertmanager,
  `defaultRules`) and how flags reach VMSingle.
- The VictoriaMetrics operator chart's default resources and CRD handling
  under Flux.
- Grafana generic OAuth for the Grafana version the chart pins:
  `role_attribute_path`, `allow_assign_grafana_admin`, the redirect URI,
  and `envFromSecret` or `envValueFrom` for the secrets.
- The CloudNativePG Grafana dashboard: which metrics and datasource type it
  needs, and how it is loaded (chart `cluster` or the JSON through the
  Grafana sidecar).
- `VMPodScrape` for the CloudNativePG instances: label `cnpg.io/podRole:
  instance`, port `metrics`, all namespaces.

**Build**
- Item `grafana` in vault `homelab-cluster`; client `grafana` in realm
  `lab` (standard flow, redirect URI
  `https://grafana.lab.savdert.com/login/generic_oauth`), created with
  `kcadm.sh` and written into the `KeycloakRealmImport`.
- Namespace `observability`, pod security level `privileged` because
  node-exporter needs the host network and PID namespace; the other pods
  keep the chart's own security contexts.
- The chart from its OCI repository through an `OCIRepository` and one
  `HelmRelease`: VMSingle on local-path storage, VMAgent, kube-state-metrics,
  node-exporter, Grafana. kube-proxy, etcd, scheduler and controller manager
  scraping off; Prometheus conversion off (D42).
- A `VMPodScrape` for every CloudNativePG instance and one for the
  operator, the CloudNativePG dashboard, an `ExternalSecret` on item
  `grafana`, and an `HTTPRoute` through Gateway `lab`.

**Decide here**
- Whether vmalert and Alertmanager stay. The dashboards rely on recording
  rules that vmalert evaluates; Alertmanager has no receiver yet. Record
  the outcome with D42. Decided: vmalert stays, Alertmanager off (D42).
- Retention and the VMSingle volume size, from the chart default and the
  data disk (100 GiB per node). Decided: 30 days, 20 GiB (D42).

**Prove here**
- Grafana reaches the issuer at `keycloak.lab.savdert.com` from inside the
  cluster through the Gateway (Homepage did, phase 9).
- VMAgent scrapes every node's kubelet and cAdvisor on Talos.

**Gate**
1. `kubectl -n observability get pods` shows every pod ready, and
   `flux get hr -n observability` shows the release ready.
2. Every scrape target is up: `kubectl -n observability port-forward
   svc/<vmagent> 8429` and `curl -s localhost:8429/api/v1/targets | jq
   '[.data.activeTargets[] | select(.health != "up")] | length'` prints `0`.
3. Replication is in the store: the query
   `cnpg_pg_replication_streaming_replicas{namespace="database"}` against
   VMSingle returns 2 for the primary of cluster `postgres`.
4. From the owner's device: `https://grafana.lab.savdert.com` sends the
   sign-in to Keycloak realm `lab`, the login from item `keycloak-lab-user`
   is accepted, a node dashboard shows CPU and memory for `k8s-1` to
   `k8s-3`, and the CloudNativePG dashboard shows cluster `postgres` with
   two streaming replicas.
5. The tool fits its budget. The cluster has no metrics API (D40), so the
   kubelet's stats summary is read for each node and the working set of
   every pod in `observability` is summed:
   `for n in k8s-1 k8s-2 k8s-3; do kubectl get --raw
   /api/v1/nodes/$n/proxy/stats/summary; done | jq -s '[.[].pods[] |
   select(.podRef.namespace == "observability") | .memory.workingSetBytes]
   | add / 1048576'` prints less than 2048 (MiB).
6. Delete the VMSingle pod; once it is ready again, the query in step 3
   still returns data from before the deletion.

**Guide**: `docs/guide/10-monitoring.md`.

## Phase 11: rebuild and restore drill

Destroy the three nodes and rebuild the cluster from Git alone, with both
databases restored from their archives. This is the only way to prove
that Git and the bucket are enough to get the lab back (review of
2026-11-17, V1), and it is the database recovery practice the lab exists
for. Alerting, the phase the review placed before this one, is being
prepared by the owner separately and is not part of the roadmap yet.
(That was the state on 2026-11-17; alerting is now phase 12, and the
owner prepares nothing separately.)

The owner approved `tofu destroy` of the lab VMs (pool `homelab`, VMs 201
to 203) on 2026-11-17 for this drill only. Settled: both clusters
bootstrap by recovery from their previous archive and archive under a new
server name (D45).

**Needs from the owner**
- Nothing new. The drill starts after phase 7 follow-up 6b is closed, so
  that the plugin's retention run is seen on the old archive first.

**Read first** (done 2026-11-17, sources in D45)
- CloudNativePG recovery through the Barman Cloud plugin:
  `bootstrap.recovery.source`, `externalClusters[].plugin`, the empty
  archive check, `serverName`.
- What recovery does with the application database, its owner and the
  `<cluster>-app` Secret.
- Retention of the plugin when the server name changes.
- `talosctl upgrade-k8s`; how the installer image and the disk image
  relate after a Talos upgrade.
- flux-operator: how to tell that the FluxInstance is installed.

**Build** (before the destroy)
- `bootstrap:flux` ends when the two bootstrap releases are adopted and
  prints how to watch the rest (V10).
- `talos:upgrade-k8s` (D17, V11).
- A pull request, merged only after the destroy, that gives both clusters
  `bootstrap.recovery` from their current archive and a new server name
  (D45).

**Prove here**
- The plugin accepts the new server name as an empty archive and starts
  archiving; the old archive is untouched.
- Keycloak starts against the recovered `keycloak-db` with its realms,
  users and clients as before; the generated `keycloak-db-app` Secret
  works with the recovered role.
- A cluster created by recovery reconciles cleanly afterwards with
  `bootstrap.recovery` still in Git.
- New VMs boot from the disk image pinned in `infra/main.tf` and install
  the version from the installer image (V18).
- Flux adopts Cilium and flux-operator without a pod restart (D33).

**Gate**
1. Before the destroy: marker row and user exist, then a backup of each
   cluster completes after them.
   - `kubectl -n database exec postgres-1 -c postgres -- psql -d app -tc
     'select note from drill_marker'` prints the marker (run on the
     primary; created with `create table drill_marker`).
   - `kcadm.sh get users -r lab -q username=drill-marker` (Keycloak guide,
     check step 3) returns one user.
   - `kubectl get backup -A` shows a `completed` backup of each cluster
     younger than the markers.
   - A listing of `s3://homelab/cnpg/` shows prefixes `postgres/` and
     `keycloak-db/` only.
2. `tofu destroy` plan lists VMs 201 to 203 and nothing else; then the
   rebuild of guide 02, "Rebuild the cluster from nothing", with the
   recovery pull request merged after the destroy.
3. `kubectl get nodes` shows three nodes Ready; `flux get ks -A` and
   `flux get hr -A` show every object Ready.
4. `kubectl cnpg status` for `postgres` and `keycloak-db`: healthy, WAL
   archiving OK; `kubectl get cluster -A -o jsonpath` shows
   `ContinuousArchiving` True; a new backup of each completes.
5. The two commands of step 1 return the marker row and the user; the
   owner signs in to Grafana and Homepage through realm `lab`.
6. A listing of `s3://homelab/cnpg/` shows the old prefixes with their
   objects unchanged and new prefixes `postgres-g2/` and `keycloak-db-g2/`
   holding WAL and a base backup.
7. After one Flux interval, `flux get ks postgres keycloak` still Ready
   with the recovery manifest applied.
8. The time of each rebuild step is written into the guide.

**Guide**: `docs/guide/11-rebuild.md`.

## Phases 12 to 16: monitoring, the lab's own

Planned on 2026-11-17 from the gaps listed in D46. The lab builds these as
if the owner's `obenhub` did not exist (D46). They run in this order:
delivery first, because every later alert is worthless without it; then
the alerts that guard data (backups, the pool); then logs and the control
plane. Backups come before the host because they need nothing from the
owner and are what is left when a disk of the striped pool dies; logs
come after the host because they add writes to a pool whose health
nothing watches yet. The owner may swap 15 and 16. Every phase that adds
pods to `observability` repeats the memory gate of phase 10. External facts below were read on
2026-11-17 and carry their source; anything marked unverified is checked
in the phase's "Read first" before it is built on.

## Phase 12: alert delivery and dead man's switch

An alert reaches the owner's phone, and silence from the lab raises an
alarm somewhere outside it. Today vmalert runs with `-notifier.blackhole`
and Alertmanager is off (D42); the whole stack sits in the cluster it
watches, on one host.

**Needs from the owner**
- One thing, asked for when the phase reaches it and not before (owner,
  2026-11-17): a Telegram bot of the lab's own. When the receiver is
  the next thing to build, the architect tells the owner; the owner
  creates the bot, sends it one message so that it may answer, and
  gives the token and chat id, or the name of the item holding them.
  Everything else in the phase goes on meanwhile and the owner prepares
  nothing else, the note in phase 11 included. The rest reuses what the
  owner already runs for
  `perp-live` on the agent box, read in that repository on 2026-11-17
  (`docs/decisions/0002-canary-monitoring.md`,
  `docs/operations/monitoring.md`, `src/perplive/alarm.py`):
  - Heartbeat: the owner's healthchecks.io account. Its API key and
    project ping key are item `Healtchecks API` (spelled so) in vault
    `dotfiles`; `perp-live` creates its checks through the management
    API and pings `hc-ping.com/<ping key>/<slug>`. Its dead man's check
    alarms by email and a Bark push, both outside the host.
  - Notification: Alertmanager's own Telegram receiver with the lab's
    new bot. The bot `perp-live` pushes through (item `Hermes`, vault
    `dotfiles`) is not used, so no secret of `dotfiles` is copied into
    the cluster.
- The architect creates one check, `homelab-watchdog` (tag `homelab`),
  and attaches the channels the `perp-live` check has; which those are
  is read from the account, not from `perp-live`'s code, where the owner
  attached them by hand. The authority is the owner's instruction of
  2026-11-17 to use this account. The account also holds the dead man
  of `perp-live`, and the API key can change every check in it, so:
  count the checks first, create this one and nothing else, never update
  or delete an existing check, and show the owner the exact API call and
  the 1Password item write (fields, not values) in the pull request
  description before running either. No reply is waited for (owner,
  2026-11-17); the rule asks that the owner sees the plan. This handles credentials and writes to
  a live system outside Flux, so it takes the audit of that tier
  ([Standards](standards.md)).
- What the cluster needs becomes item `alertmanager` in vault
  `homelab-cluster`: the new check's own ping URL, not the project ping
  key, which could keep every check of the account alive, and the
  notification credential. The API key and ping key are read with the
  workstation's own account, the only one that reads `dotfiles`; the
  item is written with the `homelab` account, the only one that writes
  `homelab-cluster`; values pass in memory, never through a file. The
  item and its fields go into the table of
  [Architecture](architecture.md), "Secrets". The cluster never reads
  vault `dotfiles`.

**Read first**
- The pinned chart's values `alertmanager.enabled`, `alertmanager.spec`,
  `alertmanager.spec.configSecret` (when set, `alertmanager.config` is
  ignored) and the template `vmalert/notifiers.yaml`, which wires vmalert
  to Alertmanager only when it is enabled. Unverified: whether
  `notifier.blackhole` conflicts with that wiring; plan to remove it.
- Whether the synced default rules contain an always-firing `Watchdog`:
  `kubectl get vmrule -A -o yaml | grep -n Watchdog`. Unverified; if it
  is missing, the lab adds its own.
- The Alertmanager version the chart ships and its receiver syntax for the
  chosen channel; the healthchecks.io ping API and that it accepts
  Alertmanager's webhook POST (unverified).
- How to stop the `Watchdog` from leaving the cluster for gate 4.
  Alertmanager is a `VMAlertmanager` object that the operator reconciles,
  so suspending the HelmRelease and scaling its StatefulSet is probably
  undone at once (unverified). Candidates: scale the operator to zero
  first, or pause the object, or stop vmalert. Confirm one on the running
  version and write it into the guide.
- healthchecks.io: how many checks the account already holds against the
  free plan's 20, whether the API key may attach existing channels to a
  new check, and a period and grace for `homelab-watchdog` that fit the
  `Watchdog` repeat interval (`perp-live` uses 300 s and 900 s).
- What fires today: `ALERTS{alertstate="firing"}` against VMSingle
  (unverified: that vmalert writes `ALERTS` back to the store in this
  chart; otherwise vmalert's own `/api/v1/alerts`). Every
  alert in that list is either fixed, or switched off with a reason (the
  rules for targets D42 does not scrape are the likely ones).

**Build**
- An `ExternalSecret` on item `alertmanager` that renders the Alertmanager
  configuration; Alertmanager with one replica, pointed at it.
- vmalert without the blackhole flag.
- A rule for the path the `Watchdog` does not cover. The `Watchdog` proves
  vmalert, Alertmanager and the way out; it says nothing about vmagent
  having stopped scraping (assumption: its expression does not depend on
  scraped series). One rule alerts when no fresh `up` samples arrive.
- Routes: `Watchdog` to the `homelab-watchdog` ping URL with
  `send_resolved: false`
  and a repeat interval shorter than the check's period; everything else
  to the owner's channel, grouped so that one fault is one message.

**Decide here**
- Nothing about the channel: ordinary alerts go to Telegram through the
  lab's own bot (owner, 2026-11-17). If the bot cannot post to the
  owner's chat, stop and ask; email has no credentials named anywhere
  and is not a silent fallback.
- Whether the default rules and dashboards stay unpinned (D42). Once rules
  page a person, a change upstream changes what pages without a pull
  request. Criteria: pin (copies in Git, or the chart's sync switched off)
  if the Read-first list shows default alerts that had to be switched off;
  otherwise keep D42 and say so.
- Whether Alertmanager gets an `HTTPRoute`. It has no login of its own;
  default is no route, port-forward only.
- Silences and notification state: `emptyDir` or a volume.
- Platform alerts the default rules may lack: an `ExternalSecret` that
  stops syncing, a certificate close to expiry, a Flux object that stops
  reconciling. Each needs its controller scraped; take the ones whose
  metrics are already in the store, record the rest as a gap.
- The real fault for gate 3: one the architect can provoke and undo
  without the owner, on something the default rules watch.

**Prove here**
- The stack still fits the 2048 MiB budget of D42 with Alertmanager added
  (1310 MiB measured after 7.5 h in phase 10). If not, stop and ask.

**Gate**
1. `kubectl -n observability get pods` shows every pod ready, `flux get hr
   -n observability` ready. The running vmalert pod's arguments, not only
   the `VMAlert` object, carry no `blackhole` and name the Alertmanager:
   `kubectl -n observability get pods -o yaml | grep -c blackhole` prints
   `0` (grep then exits 1), and vmalert's notifier list shows the
   Alertmanager address.
2. A synthetic alert (a temporary `VMRule` with `expr: vector(1)`, applied
   and removed by the architect) is delivered, and its resolution after
   removal: Alertmanager's notification counter for the receiver rises
   and its failure counter does not.
3. One alert of the default rules, provoked by the fault chosen in
   "Decide here", is delivered and so is its resolution, by the same
   counters.
4. Dead man: stop the `Watchdog` with the method confirmed in "Read
   first" and check that Alertmanager or vmalert is in fact down; the
   healthchecks.io API shows `homelab-watchdog` down within its grace
   time and a notification sent; this pages the owner once, by email and
   Bark, so say so beforehand. Undo it; the check is up again.
5. One hour later the firing alerts, read the way "Read first" settled,
   are `Watchdog` only, and vmalert reports no rule group with an
   evaluation error.
6. With vmagent stopped, the no-samples rule arrives; it resolves after
   vmagent is back.
7. The memory command of phase 10, gate 5, prints less than 2048.

**Guide**: `docs/guide/12-alerting.md`.

## Phase 13: backup and database alerts

The lab is told when a backup or WAL archiving stops, for both
CloudNativePG clusters. Today the only check is a person reading
`kubectl get backup -A`.

**Needs from the owner**
- Nothing new.

**Read first**
- The live `/metrics` of one instance pod of each cluster. Backups go
  through the Barman Cloud plugin, whose metrics
  `barman_cloud_cloudnative_pg_io_last_available_backup_timestamp`,
  `..._last_failed_backup_timestamp` and `..._first_recoverability_point`
  supersede the `cnpg_collector_*` ones
  ([plugin observability](https://cloudnative-pg.io/plugin-barman-cloud/docs/observability/)).
  Unverified: that the existing `VMPodScrape` on port `metrics` already
  collects them, and what the old names show with plugin backups.
- Which instances carry the backup series (primary only, or replicas
  too) and what a cluster shows that has never completed a backup: zero,
  or no series. The rules must alert in that case as well, not return
  nothing.
- The archiver series (`cnpg_pg_stat_archiver_*`, name inferred from the
  default monitoring queries; primary only) and
  `cnpg_collector_pg_wal_archive_status`.
- CloudNativePG's sample alert rules. Anything copied records file,
  licence and commit beside it.
- `vmalert-tool unittest` for the pinned vmalert version.

**Build**
- One `VMRule` in Git, the lab's own: last successful backup older than
  the daily schedule allows; a failed backup newer than the last
  successful one; WAL archiving failing or files waiting to be archived
  piling up; a cluster with fewer ready instances or streaming replicas
  than it declares.
- Unit tests for those rules. `vmalert-tool` is not in `mise.toml` today:
  add it there with a lint task that `check` depends on.

**Decide here**
- Thresholds, from the schedules (03:00 and 03:30 UTC daily) and what the
  series look like over a few days.
- Whether volume fill alerts belong here. Unverified: that kubelet volume
  statistics exist for local-path volumes.

**Prove here**
- Each alert fires on a real fault, on a throwaway CloudNativePG cluster
  in its own namespace: archiving fails, an on-demand backup fails. The
  real object-storage key can write the whole bucket, so the throwaway
  cluster never gets it: its `ObjectStore` carries a made-up access key
  in a Secret of its own, which cannot write anywhere, and the cluster
  and its server name are none of `postgres`, `postgres-g2`,
  `keycloak-db`, `keycloak-db-g2`. Unverified: that a cluster with a
  refused key starts and then reports failed archiving, rather than never
  becoming ready; if it does not start, change the fault (an unreachable
  endpoint) and keep the rule about the key. The throwaway cluster is
  removed in the same phase.
- What is proven live and what by unit test. Live, on the throwaway
  cluster: archiving failing, a failed backup, a cluster that never had
  a backup, and a missing replica (delete one of its instances). By unit
  test only: backup age, which would need a day of waiting, and that a
  later successful backup clears the failed-backup alert, which the
  throwaway cluster cannot produce without the real key. Its alerts
  resolve because its series end, which proves nothing about recovery.

**Gate**
1. vmalert lists the group with every rule healthy; `mise run check`
   passes with the unit tests.
2. On the throwaway cluster the alerts listed as live in "Prove here"
   each arrive on the owner's device; the unit tests cover the rest, a
   recovery after a failed backup among them.
3. A listing of `s3://homelab/cnpg/` before the throwaway cluster and
   after its removal shows the same prefixes (the check of phase 11,
   gate 1).
4. For `postgres` and `keycloak-db` the last-backup metric chosen in
   "Read first", queried from VMSingle, agrees with the newest
   `completed` object of `kubectl get backup -A`.
5. One day later, after the scheduled backups, nothing from this group
   fires.
6. The memory command of phase 10, gate 5, prints less than 2048.

**Guide**: `docs/guide/13-backup-alerts.md`.

## Phase 14: Proxmox host and ZFS

The host's CPU, memory, disks and the state of `rpool` are in the store
and alert. The pool is a striped pair without redundancy and the host has
no scheduled backups ([Host](host.md)), so the first sign of a failing
disk matters. A stripe does not degrade: when a disk goes, the pool
faults and the cluster, Alertmanager included, stops with it (assumption,
not tested and not testable here). That case is covered only by the dead
man's switch of phase 12. What this phase can add is warning before it:
the disks' own error and wear counters.

**Needs from the owner**
- The host change itself (AGENTS.md, "Proxmox safety"): the owner installs
  and starts the exporter on the host, or approves the exact commands.
- Whether guests outside pool `homelab` may appear in the lab's metrics.
  If yes, and a per-guest view is wanted, a read-only API token
  (`PVEAuditor`).

**Read first**
- `node_exporter` as packaged for the host's Debian release: version, and
  that its `zfs` collector exports `node_zfs_zpool_state{zpool,state}`
  ([source](https://github.com/prometheus/node_exporter/blob/master/collector/zfs_linux.go)).
- Where pool capacity and disk errors come from. The linked collector
  source shows pool state and I/O; pool size and allocation, and a
  per-disk error series, are unverified. If `node_exporter` lacks them,
  the rule list below shrinks or a textfile collector is decided here.
- NVMe wear, media errors and SMART, which are the early warning on this
  pool: not in `node_exporter`'s defaults as far as read. Find the source
  (a SMART exporter, or a textfile collector fed by `smartctl` or `nvme`)
  and its licence. Also ZFS read, write and checksum error counts per
  device, source unverified.
- How the pinned operator scrapes a static address outside the cluster
  (`VMStaticScrape` or `VMScrapeConfig`).
- Why not Proxmox's own OpenTelemetry metric server (pve-manager 9.0 and
  later; JSON body per its
  [patch](https://lists.proxmox.com/pipermail/pve-devel/2025-July/073437.html)):
  it sends OTLP as JSON, VictoriaMetrics accepts protobuf only
  ([VictoriaMetrics OpenTelemetry](https://docs.victoriametrics.com/victoriametrics/integrations/opentelemetry/)),
  so it would need a collector in between, and it reports pool capacity
  but, as far as read, not pool health.

**Build**
- The exporter on the host, listening on the lab gateway address
  10.0.6.1 only.
- A static scrape, a host dashboard, and a `VMRule`: target down, pool
  state anything but online, NVMe media errors or wear past a threshold,
  memory and load sustained, and pool nearly full and ZFS device errors
  if "Read first" found their series.

**Decide here**
- `node_exporter` alone, or with
  [`prometheus-pve-exporter`](https://github.com/prometheus-pve/prometheus-pve-exporter)
  (Apache-2.0 per its repository, API token) for per-guest figures.
  Criteria: the owner's answer above and the memory budget. A second
  token contradicts AGENTS.md, "Proxmox safety", which names
  `homelab@pve!tofu` as the only one: choosing it means a decision
  record, that rule updated, and the new item in the table of
  [Architecture](architecture.md).
- Who may reach the exporter. It has no login, and 10.0.6.0/24 is
  advertised to the tailnet and reachable from `vnet0` (D21). Default:
  the owner restricts the port to the three node addresses; leaving it
  open is a recorded decision.
- If no SMART source fits (footprint, licence, what the owner will run
  on the host): stop and tell the owner; without it the phase gives no
  warning ahead of a disk failure.

**Prove here**
- Pods reach 10.0.6.1 on the exporter's port (no host firewall rule is
  recorded in this repository).
- `node_zfs_zpool_state` is present for `rpool`.

**Gate**
1. The host target is up in vmagent's target list.
2. `node_zfs_zpool_state{zpool="rpool",state="online"}` returns 1.
3. The pool-state rule passes unit tests with the pool degraded, faulted
   and suspended; none can be provoked on a pool without redundancy.
   The disk-health series of both NVMe disks are in the store.
4. The owner stops the exporter; the target-down alert arrives, and
   resolves after the restart.
5. The host dashboard shows CPU, memory and disk I/O, and pool capacity
   if its series exists.
6. The memory command of phase 10, gate 5, prints less than 2048.

**Guide**: `docs/guide/14-host.md`.

## Phase 15: logs

Pod logs, the PostgreSQL logs among them, are kept for a few days and can
be searched from Grafana after the pod is gone.

**Needs from the owner**
- Nothing new.

**Read first**
- The `victoria-logs-single` and `victoria-logs-collector` charts (the
  collector is a DaemonSet of `vlagent` that mounts `/var/log` and
  `/var/lib` read-only,
  [chart docs](https://docs.victoriametrics.com/helm/victoria-logs-collector/)):
  values, resources, and the namespace's pod security level.
- That pod logs on Talos are where the collector expects them. Unverified.
- The VictoriaLogs datasource for the pinned Grafana and how the chart
  installs a plugin.

**Build**
- VictoriaLogs with a volume on local-path, the collector, the Grafana
  datasource.

**Decide here**
- Retention and volume size, from one day of measured ingestion.
- The memory budget for logs, as a new record; the 2048 MiB of D42 was
  set for metrics. The record states the total for metrics and logs
  against what the nodes have free, and the CPU the collector takes on a
  host whose scarce resource is CPU (D20).

**Prove here**
- CloudNativePG's JSON log lines arrive with fields that can be filtered
  by cluster and instance.

**Gate**
1. Every pod ready, HelmReleases ready.
2. A query for one instance pod of `postgres` returns its PostgreSQL log
   lines.
3. A pod logs a marker line; once a query returns it, delete the pod;
   the line is still returned afterwards.
4. Memory of the logs pods is under the budget decided here.
5. Delete the VictoriaLogs pod; the marker line of step 3, whose pod no
   longer exists and cannot be read again, is still returned.

**Guide**: `docs/guide/15-logs.md`.

## Phase 16: control plane metrics

etcd, the scheduler and the controller manager are scraped, with their
default alerts and the etcd dashboard switched on. D42 left each as "a
later change with its own record".

**Needs from the owner**
- Approval of a rolling machine-configuration change on all three nodes,
  possibly with a reboot each; it is run like an upgrade drill (D23).

**Read first**
- The etcd patch in the Talos documentation for the running version:
  `cluster.etcd.extraArgs.listen-metrics-urls: http://0.0.0.0:2381`
  ([Sidero docs](https://docs.siderolabs.com/kubernetes-guides/monitoring-and-observability/etcd-metrics)).
  The port is plain HTTP without authentication.
- Scheduler and controller manager: no official Talos page was found;
  community reports use `bind-address: 0.0.0.0` in their `extraArgs`
  (ports 10259 and 10257, HTTPS). Unverified, as is a report that newer
  Talos versions reject these fields beside their own config documents.
- The chart's `kubeEtcd`, `kubeScheduler` and `kubeControllerManager`
  values with explicit endpoints; its selectors expect pods Talos does
  not run.

**Build**
- The machine-configuration patches, applied one node at a time with etcd
  health checked in between; the scrape switches and the dashboard.

**Decide here**
- The unauthenticated metrics port on the node address. Default: a
  Cilium policy that admits vmagent only; leaving it open is a recorded
  decision.
- Whether the scheduler and controller manager are worth the change if no
  documented way exists; etcd alone is an acceptable outcome.

**Prove here**
- The change needs no cluster rebuild, and a node returns Ready after it.

**Gate**
1. `talosctl etcd members` and `kubectl get nodes` are healthy after each
   node.
2. The etcd targets are up, three; so are the scheduler's and the
   controller manager's if "Decide here" kept them.
3. The etcd dashboard shows three members and a leader.
4. The default alerts of the components kept are loaded and none fires
   at rest.
5. The memory command of phase 10, gate 5, prints less than 2048.

**Guide**: `docs/guide/16-control-plane.md`.
