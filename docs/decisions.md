# Decisions

Settled design decisions, newest last. Each record gives the choice, what it
was chosen over, the reason and the evidence. Evidence labels:

- **tested**: run against this host on the date given;
- **docs**: read in the project's current documentation;
- **reference**: seen in onedr0p/home-ops, buroa/home-ops (formerly
  k8s-gitops) or onedr0p/cluster-template;
- **judgment**: the architect's reasoning, no external proof.

New decisions are appended with the next number. A decision is changed only
by a new record that names the one it replaces.

## D01 Node OS: Talos Linux, three nodes, each control plane and worker

Over: a kubeadm or k3s cluster on a general-purpose distribution.
Reason: immutable, API-driven nodes make upgrades and rebuilds repeatable.
Three nodes on one host give no redundancy; they exist to practise upgrades,
drains and quorum. Evidence: owner's choice, 2026-11-14.

## D02 VM provisioning: OpenTofu with bpg/proxmox, not Terraform

Reason: OpenTofu has client-side state encryption; Terraform has only
server-side options, and its state holds secrets in plain text. State has to
live off a disposable workstation, so encryption decides it. Licence is not
the reason: the BUSL permits private use. Cost: bpg/proxmox supports
OpenTofu but does not exercise it in CI. Evidence: docs (opentofu.org state
encryption; bpg provider index), 2026-11-14.

## D03 Proxmox access: a token confined to pool `homelab`

Over: the administrator token. Role `HomelabVM` on `/pool/homelab` (which
contains storage `local-zfs`), `PVESDNUser` on `/sdn/zones/localnat/k8s`,
`HomelabImageRead` (Datastore.Audit) on `/storage/local`. Evidence: tested
2026-11-15 with a throwaway VM: create with disk import, resize, start,
guest agent, stop and destroy all succeeded; reading, stopping and creating
guests outside the pool returned 403. Exact privileges: `docs/host.md`.

## D04 Network: a dedicated SDN VNet `k8s`, 10.0.6.0/24

Over: sharing `vnet0` (10.0.0.0/24) with the unrelated lab guests and the
agent box. Reason: a wrong virtual IP or address announcement must not be
able to disturb those guests, and the lab gets its own address plan.
Evidence: tested 2026-11-15: applying the SDN change lost 0 of 150 pings on
`vnet0` (twice); the box reaches the new subnet through the host gateway.
The subnet was first created as 10.0.1.0/24 and moved to 10.0.6.0/24 at the
owner's request the same day; the node test in D05 ran on the first one.

## D05 Node image: Image Factory `nocloud` qcow2, addresses from cloud-init

Over: the metal ISO from the Talos Proxmox guide. Reason: nodes come up at
known static addresses on first boot without DHCP discovery, snippets or
SSH to the host. Schematic: `siderolabs/qemu-guest-agent` only. Evidence:
tested 2026-11-15 with Talos v1.14.6: the VM answered
`talosctl get disks --insecure` at the address set in `ipconfig0`; the
install disk is `/dev/sda`. Not yet tested: applying a machine config and
upgrading on this image (phase 2).

## D06 Machine configuration: talosctl patches, secrets from 1Password

Over: talhelper (archived 2026-08-26), the siderolabs/talos OpenTofu
provider (cluster secrets land in state; open upgrade issues), Omni. Plain
YAML patch files with `op://` references, rendered by `op inject` and merged
with `talosctl machineconfig patch`. No template engine: three identical
nodes do not need one. Evidence: reference (both home-ops repositories use
this shape with a template engine on top), docs.

## D07 API endpoint: Talos layer-2 virtual IP 10.0.6.10

Over: a DNS name or an external load balancer. Reason: documented Talos
feature for control planes on one layer-2 segment; no extra component.
Evidence: docs (Layer2VIPConfig, Talos v1.14 reference). Not yet tested.

## D08 CNI: Cilium replacing kube-proxy, installed during bootstrap

Reason: Talos nodes do not become Ready without a CNI, so Cilium cannot wait
for Flux. Talos v1.14 form: delete the `KubeFlannelCNIConfig` document and
set `KubeProxyConfig` `enabled: false`. Evidence: docs (Talos Cilium guide),
reference (cluster-template uses exactly this pair).

## D09 Bootstrap: Cilium, then Flux Operator, then a FluxInstance

Over: the longer bootstrap lists of the reference repositories (CoreDNS,
Spegel, cert-manager, External Secrets). Everything else is installed by
Flux. CoreDNS stays the one Talos deploys. Bootstrap is a set of mise tasks.
The chart version and values Cilium is bootstrapped with live in
`kubernetes/apps/kube-system/cilium/app/`, created in phase 2 because
phase 2 uses them. Phase 3 points Flux at the same files, so Flux adopts
the release instead of reinstalling it. Evidence: reference (home-ops bootstrap README), judgment
for the shorter list.

## D10 GitOps: Flux from the public repository, polling

No Git credential (the repository is public) and no webhook receiver (the
cluster is not reachable from the internet). Evidence: docs (Flux
GitRepository: `secretRef` optional for public repositories).

## D11 Secrets: External Secrets Operator, 1Password SDK provider (vault changed by D25)

Over: 1Password Connect, which the External Secrets documentation marks as
superseded. One `ClusterSecretStore` on vault `homelab`, authenticated by
that vault's own service account. The service-account token is the single
secret applied by hand at bootstrap. Evidence: docs, reference (buroa).

## D12 Ingress: Envoy Gateway behind the Tailscale operator (replaced by D21)

The Envoy proxy Service is `type: LoadBalancer` with
`loadBalancerClass: tailscale`; nothing is exposed on the public address.
Over: Tailscale Ingress class (bypasses Gateway API), Cilium Gateway API
(would drop a component, but the Tailscale guide and both reference
repositories use Envoy Gateway), a subnet router. Evidence: docs (Tailscale
"bring your own Gateway API" guide). The operator has no native Gateway API
support.

## D13 TLS and names: cert-manager wildcard for `*.lab.savdert.com` (record target changed by D21)

DNS-01 through Cloudflare. One public wildcard A record points at the
tailnet address of the gateway, so no internal resolver or ExternalDNS is
needed. Over: `ts.net` certificates (one name per device), split DNS with an
internal resolver (the Tailscale guide's way; more components). Cost: a
tailnet address is visible in public DNS; it is not routable from outside.
Evidence: docs for cert-manager and Envoy Gateway; the public record
pointing at a tailnet address is judgment and is proven in phase 5.

## D14 Storage: local-path-provisioner on a second virtual disk

A Talos `UserVolumeConfig` on `/dev/sdb`, mounted under `/var/mnt`. Over:
proxmox-csi-plugin (volumes can move between nodes, but it puts a Proxmox
credential with disk-allocation rights inside the cluster, next to
unrelated guests), ZFS or LVM inside the VM, democratic-csi over SSH.
Consequence: volumes are bound to a node. CloudNativePG is designed for
this (one instance per node, switchover on drain). A single-replica
application waits for its node to return. No CSI snapshots. Evidence: docs
(Sidero local storage guide), judgment.

## D15 Database backup: CloudNativePG Barman Cloud Plugin to object storage

Kept because backup and point-in-time recovery drills are a purpose of the
lab, not because the data matters: this is a lab and losing it is
acceptable to the owner. Over: in-tree `barmanObjectStore` (deprecated,
removal announced for 1.32), volume snapshots (not available with D14), an
object store inside the cluster (one more component, and a restore from the
same disks is a weaker drill). Target: an S3-compatible bucket outside the
host. Evidence: docs (CloudNativePG backup page, plugin documentation).

## D16 No other backups

No etcd snapshot schedule, no vzdump, no volume backup for applications. If
the cluster is lost it is rebuilt from this repository; application data in
it is disposable. An etcd snapshot and restore can be run once as a drill;
it is not a standing job. Evidence: owner's statement, 2026-11-15. For the
record: the host's ZFS pool is a two-disk stripe and has no backup jobs.

## D17 Upgrades: by hand with talosctl, version bumps proposed by Renovate

`talosctl upgrade` and `talosctl upgrade-k8s` as mise tasks. Over: an
upgrade controller (tuppr). Reason: practising upgrades is a purpose of the
lab; a controller hides the procedure. Renovate runs as the hosted GitHub
app. Evidence: docs, reference (home-ops keeps manual tasks as well).

## D18 Documentation site: Markdown in `docs/`, built with Zensical

Published to GitHub Pages by a workflow. Over: MkDocs Material (maintenance
mode until 2027-05), Astro Starlight (needs a Node project and front matter
on every page), Docusaurus, mdBook. Zensical is the Material team's
successor and reads `mkdocs.yml`, so the content stays plain Markdown and
MkDocs Material remains a drop-in fallback. Evidence: see `docs/handoff.md`
for the local build result.

## D19 Agents: Opus architect, Sonnet implementers, Haiku for mechanical work

Project agents in `.claude/agents/`. Reason and routing rules are in
`AGENTS.md`. Evidence: docs (Claude Code subagents; Anthropic's model
selection guidance, 2026-11-09): spec-driven work suits Sonnet, small
models suit work where a mistake is cheap to spot, judgment and edits that
depend on it stay on the main model.

## D20 Node size: 2 vCPU, 8 GiB, 20 GiB system disk, 100 GiB data disk

Host on 2026-11-15: 12 threads with a load average near 10, 126 GiB RAM
with 48 GiB free, 1.5 TiB free on the pool. CPU is the scarce resource, so
nodes start at 2 vCPU. Evidence: tested (host inventory through the API).

## D21 Ingress: Envoy Gateway on a Cilium-announced address, reached through the existing Tailscale subnet router

Replaces D12. The Proxmox host is already a Tailscale subnet router that
advertises 10.0.0.0/24, and the tailnet policy grants members access to
it. The lab subnet 10.0.6.0/24 is advertised the same
way since 2026-11-15. The Envoy proxy Service is a `LoadBalancer` whose address comes from a
Cilium LB-IPAM pool (10.0.6.20 to 10.0.6.29) and is announced on the VNet
with Cilium layer-2 announcements. The wildcard record `*.lab.savdert.com`
points at 10.0.6.20. Over: the Tailscale operator (an OAuth client with
write scopes stored in the cluster, extra tags, a proxy per Service, and an
open question about Cilium socket load balancing). Envoy Gateway is kept
over Cilium's built-in Gateway API although the original reason (the
Tailscale guide) is gone: both reference repositories run Envoy Gateway on
Cilium clusters, and its upgrades stay independent of CNI upgrades, which
this lab rehearses. The price is one controller and one proxy deployment.
Gains: no Tailscale
component or credential in the cluster, and the owner's devices also reach
the Kubernetes and Talos APIs. Cost: every tailnet member with the grant
reaches the whole subnet; the APIs have their own authentication. Guests on
`vnet0` can also reach the subnet through the host. Evidence: tested
2026-11-15 (policy and device routes read with the read-only Tailscale
client). Layer-2 announcement on the Proxmox bridge is proven in phase 5.

## D22 Change flow: short branches, squash-merged pull requests, releases by release-please

Modelled on the owner's obenhub repository. Every change is a short-lived
branch and a pull request, squash-merged; no direct pushes to `main` after
the first commit. The architect merges an ordinary pull request when the
required checks are green and the audit passed. release-please keeps one
release pull request open that accumulates the changelog; it is merged only
by the owner, when the architect reports that a phase is closed. Flux
follows `main`, not release tags: there is one cluster and it is where the
gates are proven, so it has to run what is on `main` before a release can
be declared. A release therefore marks a verified state; it does not deploy
anything. Over: one long pull request per phase (the cluster would run an
unmerged branch, or the gate would be proven only after the merge), Flux
following tags (same problem). Evidence: reference (obenhub `AGENTS.md`,
`CONTRIBUTING.md`), judgment.

## D23 Dependency updates: Renovate proposes, the architect triages

At the start of every session and before closing a phase the architect
reads the Dependency Dashboard issue and the open Renovate pull requests.
It merges on its own: GitHub Actions digests, mise tools, documentation
tooling, and patch updates of charts and images, once checks are green,
and confirms the cluster is healthy afterwards. It prepares but does not
merge: Talos, Kubernetes, Cilium, Flux, CloudNativePG and PostgreSQL minor
or major updates. Those are upgrade drills; the owner decides when, and the
architect writes what changes and the procedure. Renovate configuration
problems (wrong grouping, missed files, noise) are fixed by the architect.
Evidence: owner's instruction 2026-11-15, reference (obenhub
`renovate.json` for schedule, release age and grouping).

## D24 Object storage: one bucket `homelab`, a prefix per use

Oracle Object Storage through its S3-compatible endpoint, region
us-ashburn-1, path-style addressing. Prefixes: `tofu/` for OpenTofu state,
`cnpg/<cluster>/` for database backups. Evidence: tested 2026-11-15 with
aws-cli 2.40: upload and listing work; a conditional write
(`If-None-Match: *`) on an existing key returns 412, which is what
OpenTofu's `use_lockfile` relies on; a multi-object delete fails with the
client's default CRC32 checksum and succeeds with CRC32C. The last point
matters for backup retention in phase 7: a second test with
`AWS_REQUEST_CHECKSUM_CALCULATION=when_required`, the setting the
CloudNativePG plugin documents for S3-compatible stores, was refused in the
same way. Uploads and single-object deletes work with either setting. If
the plugin's retention cannot delete on this store, the fallback is fixed:
no retention policy in CloudNativePG and an Oracle lifecycle rule that
expires objects under `cnpg/` after 14 days. The access key currently in
1Password can read every bucket of the account, not only this one.

## D25 Vaults: the cluster reads its own vault with a read-only account

Changes D11. Vault `homelab` holds what builds the lab (the Proxmox token,
the state passphrase, the Talos cluster secrets) and its service account
can write. Giving that account to External Secrets would let any workload
that can create an `ExternalSecret` read the Proxmox token and the cluster
CA keys, which is what D14 avoided for storage. The cluster therefore gets
vault `homelab-cluster` with a separate read-only service account; only
`cloudflare-dns` and later the bucket-limited `object-storage` live there.
Evidence: judgment, prompted by the external design review of 2026-11-15.

## D26 Cilium settings fixed from the first install

`rollOutCiliumPods: true` and `operator.rollOutPods: true`, so that a
changed setting (LB IPAM and layer-2 announcements in phase 5) restarts
the agents without a manual step, and Hubble disabled until monitoring is
chosen in phase 9, so that no certificate regeneration changes the release
on every reconciliation. Evidence: judgment; the chart defaults behind it
(`rollOutCiliumPods: false`, Hubble certificates generated by Helm) come
from the external design review and are confirmed against the chart's
values in phase 2 before they are relied on.

## D27 First database: fixed parameters

Namespace `database`, cluster `postgres`, three instances with pod
anti-affinity across nodes, 10 GiB per instance on the default storage
class with WAL on the same volume, a daily base backup at 03:00 UTC and
continuous WAL archiving to `cnpg/postgres/`, retention 7 days (or the
fallback in D24). The PostgreSQL major version is the newest that the
current CloudNativePG release lists as supported. Evidence: judgment; sized
for 8 GiB nodes and a drill, not for data.

## D28 Node VMs carry no Proxmox tags

Changes the node table in [Architecture](architecture.md), which listed the
tags `homelab` and `talos`. Over: granting the token `VM.Config.Options` on
`/vms/201` to `/vms/203`, which would give it rights outside pool
`homelab` (D03); and adding the tags in a second apply, which a fresh
environment could not reproduce in one run. Reason: membership of pool
`homelab` already marks the lab's VMs; the tags were only a label.
Evidence: tested 2026-11-15 with the `tofu` token on Proxmox VE 9.2.26.
Creating VM 201 with `pool=homelab` and `tags=homelab;talos` was refused
with `403 Permission check failed (/vms/201, VM.Config.Options)`; the same
create without tags, and with each other option bpg/proxmox 0.122.0 sends,
succeeded; setting the tags on the existing VM afterwards also succeeded.
Inferred, not read in the Proxmox source: at creation Proxmox checks the
tag right on `/vms/<id>` before the VM is a pool member, so the pool's
rights do not apply yet.

## D29 Kubernetes version: 1.36, the newest minor both Talos and Cilium list

Over: 1.37.1, the default of `talosctl` v1.14.6. Talos v1.14 supports
Kubernetes 1.33 to 1.37; Cilium 1.20.4 lists 1.33 to 1.36 as tested and
says nothing about 1.37. The cluster runs 1.36.6, the newest 1.36 kubelet
image on 2026-11-15. The move to 1.37 is an upgrade drill (D23) once a
Cilium release lists it. The version is `KUBERNETES_VERSION` in
`mise.toml`; Renovate tracks it through the kubelet image. `kubectl` 1.37
stays: one minor version of skew is supported. Evidence: docs (Talos v1.14
support matrix; `talos114.go` at v1.14.6 allows 1.32.0 to 1.37.99; Cilium
stable compatibility page), tested (`talosctl gen config` default, kubelet
tags on ghcr.io).

## D30 Talos and Kubernetes credentials are regenerated, not stored

Changes D06 in one point: the cluster secrets are not `op://` references
inside the patch files, rendered by `op inject`. The patches hold no
secret; the secrets file is read whole with `op read` and passed to
`talosctl gen config --with-secrets`.

Decided in phase 2 as the roadmap asked. `talosconfig` is derived from the
cluster secrets (`mise run talos:config`) and `kubeconfig` is fetched from
the cluster with it (`mise run talos:kubeconfig`). Both are written to the
repository root, which `.gitignore` excludes, and `mise.toml` points
`TALOSCONFIG` and `KUBECONFIG` at them. Nothing else holds them, so a box
rebuild loses nothing that cannot be recreated in two commands.

The secrets are one concealed field `secrets` in item `talos`, holding the
whole `talosctl gen secrets` file, instead of one field per key. The file
is always used as a whole (`gen config --with-secrets`), and passing it
whole avoids the partial certificate merge that home-ops documents for
patches that carry only a key. It is written only to a private tmpfs
directory that is removed when the command ends. Evidence: judgment;
reference (home-ops `talos/README.md` on the `ca` merge).

## D31 Installer image: the `nocloud` installer of the node schematic

Over: `metal-installer`, which `talosctl gen config` and the Talos Proxmox
guide use. The Image Factory serves a separate installer per platform;
for schematic `ce4c9805...` at v1.14.6 the `nocloud-installer` and
`metal-installer` manifests have different digests. The nodes boot the
`nocloud` image and take their addresses from cloud-init (D05), so the
installed system must stay on that platform. The image is set in
`talos/patches/cluster.yaml` and used by both install and upgrade.
Evidence: tested 2026-11-15: the registry manifests on factory.talos.dev,
and `talosctl upgrade` of k8s-1 with this image, after which the node
reported platform `nocloud`, address 10.0.6.11/24 and hostname `k8s-1`
([Cluster](guide/02-cluster.md), "Upgrade rehearsal").

## D32 Flux layout: a plain FluxInstance at an exact version, values kept in a values file

Over: the `flux-instance` Helm chart and inline `spec.values`, which
onedr0p/home-ops and buroa/home-ops use, and a `2.10.x` range in the
FluxInstance. The FluxInstance is one short manifest
(`kubernetes/apps/flux-system/flux-instance/app/fluxinstance.yaml`) that
bootstrap applies once and Flux then reconciles from Git; a chart around it
adds a release and a values layer without adding a setting the lab uses.
The Flux version is exact so that it moves only through a Renovate pull
request (custom manager on the `# renovate:` comment, upgrade drill for
minor and major, D23, which also covers the flux-operator chart); a range
would let the operator upgrade Flux on its own. The Flux CLI in `mise.toml`
is a separate pin and arrives as its own pull request; the two are merged
together. Chart values stay in `values.yaml` next to the HelmRelease, so
`bootstrap:cilium` uses the file as it is; Flux reads it through a
`configMapGenerator` ConfigMap whose hashed name `kustomizeconfig.yaml`
writes into `spec.valuesFrom`, so a changed value changes the HelmRelease
and starts an upgrade without waiting for its interval. The sync path is
`kubernetes/apps` with an explicit `kustomization.yaml` that lists the
namespace directories, as in the references, but written out instead of
generated. Evidence: docs (fluxoperator.dev FluxInstance reference:
`version` takes a semver range or an exact version; the operator creates
GitRepository and Kustomization `flux-system`, default interval 1m),
reference (both home-ops repositories, read 2026-11-15), tested
(`kubectl kustomize` renders the hashed ConfigMap name into the
HelmRelease).

## D33 Chart versions: helm-controller does not append the artifact digest

Over: the default, in which helm-controller appends the first twelve
characters of the OCI artifact digest to the chart version of every
HelmRelease that uses `chartRef` to an OCIRepository
(`cilium@1.20.4+712e1f65bf30`, label `cilium-1.20.4_712e1f65bf30`); a `postRenderers` patch per release that
rewrites the label; and `spec.chart` with a HelmRepository of type `oci`,
which would give up the OCIRepository layout of D32. Cilium and
flux-operator write the chart version into the pod label `helm.sh/chart`,
so with the default the first reconciliation after bootstrap changed every
pod template and rolled all Cilium agent, Envoy and operator pods and the
flux-operator pod, although chart and values were identical. The feature
gate `DisableChartDigestTracking=true` is set on helm-controller through
`spec.kustomize.patches` of the FluxInstance, so on a rebuild it is in
force before the first HelmRelease exists. On this cluster it came after
the first adoption and costs one more roll. The HelmRelease
API has no field for this; the gate is the documented switch. The price: a
chart pushed again under the same tag no longer starts an upgrade. The lab
does not rely on that, since chart tags move only through Renovate pull
requests (D23). Evidence: tested (lab cluster 2026-11-15: Helm revisions 1
and 2 of `cilium` and `flux-operator` differ in the pod templates only in
`helm.sh/chart` (object metadata also gains Flux ownership labels), pods
rolled at 14:55 UTC; kind cluster with flux-operator 0.62.1 and Flux
2.10.0, gate set from the same FluxInstance: flux-operator adopted at
revision 2 with chart `flux-operator@0.62.1`, deployment generation and
pod UID unchanged; the kind cluster ran on the agent box, not on this
host; lab cluster after the merge: a forced Helm upgrade of `cilium`,
revision 3 to 4, left the DaemonSet, Envoy and operator generations and
every pod UID unchanged, [Flux](guide/03-flux.md), "Check"), docs
(helm-controller v1.7.1: `docs/spec/v2/helmreleases.md`,
"Chart reference"; changelog 1.3.0, pull request 1212; and the source,
`mutateChartWithSourceRevision` in
`internal/controller/helmrelease_controller.go` and
`internal/features/features.go`), reference (onedr0p/home-ops sets the
same gate in its FluxInstance).

## D34 Gateway API CRDs: from the Envoy Gateway chart, upgraded with it; certificates are explicit

Over: the CRD-only chart `gateway-crds-helm` in its own Kustomization, and
the upstream Gateway API release applied as a Flux Kustomization. The
Envoy Gateway chart `gateway-helm` installs the Gateway API CRDs
(experimental channel, the version Envoy Gateway is built against:
Gateway API 1.6.1 in the CRDs of Envoy Gateway 1.10.0) and its own CRDs by
default, from the `crds/` directory of its subchart `crds`. Helm applies files in `crds/` on
install only, and helm-controller's default `upgrade.crds` is `Skip`, so
the HelmRelease sets `install.crds` and `upgrade.crds` to
`CreateReplace`: a Renovate update of Envoy Gateway then moves CRDs and
controller together, which is the order the Envoy Gateway upgrade notes
require. A separate chart would add a second version to keep in step with
the first; upstream Gateway API is already one minor ahead (1.7.0) of what
Envoy Gateway supports. cert-manager does not use Gateway API: the
wildcard certificate is an explicit `Certificate` that the `Gateway`
references by Secret name, so cert-manager runs without
`config.gatewayAPI.enabled` and depends on no Gateway API CRD version.
That removes the start-up ordering the roadmap's criterion guards against.
The order that remains is expressed with `dependsOn`: the `Certificate`,
the `Gateway` and its route are applied together after the Envoy Gateway
Kustomization is Ready; the `Gateway` waits for the certificate Secret, and
the Kustomization is Ready only when the `Certificate` is Ready and the
`Gateway` is Programmed. Evidence: docs (Envoy Gateway
"Install with Helm" and v1.10.0 release notes; cert-manager "Gateway API"
usage page; `kubectl explain helmrelease.spec.upgrade.crds` on the lab
cluster, 2026-11-15), source (`gateway-helm` 1.10.0 pulled and read:
`Chart.yaml` dependency `crds` with condition `crds.enabled`, CRDs under
`charts/crds/crds/`), reference (onedr0p/home-ops installs `gateway-helm`
with its default CRDs and references the certificate Secret from the
`Gateway`; it does not enable Gateway API in cert-manager).

## D35 Storage details: the upstream OCI chart, the whole data disk, Delete on release

Over: the kustomize base `github.com/rancher/local-path-provisioner/deploy`
that the Sidero local storage guide applies with three patches, and
OpenEBS hostpath, which buroa/k8s-gitops uses for the same purpose. The
project publishes its Helm chart to
`oci://ghcr.io/rancher/local-path-provisioner/charts/local-path-provisioner`
(tags are the release versions, `0.0.37` current; release candidates and
`0.0.0-master` sit beside them), so it fits the OCIRepository layout of
D32 and Renovate's flux manager; the chart sets the path, the default
class and the helper image through values instead of patches. OpenEBS is
a different product from the one D14 chose. The Talos `UserVolumeConfig`
`local-path-provisioner` selects `!system_disk` with `minSize: 50GB` (the
CD-ROM with the cloud-init data is 4 MB) and has no `maxSize`, so it takes
all of `/dev/sdb`. It does not name `/dev/sdb`: device names are not
stable, and each node has exactly one non-system disk; a second data disk
would need a narrower selector. Defaults give XFS and a
`nosuid,nodev,noexec` mount at `/var/mnt/local-path-provisioner`, so a
workload cannot run a binary from its volume; PostgreSQL data needs no
exec. It applied without a reboot on all three
nodes. The StorageClass keeps the chart's `reclaimPolicy: Delete` and
`WaitForFirstConsumer`: deleting a claim deletes its directory, which suits
a lab whose data is disposable and whose databases are restored from
object storage (D15). The helper pods' image is pinned (chart default
`busybox:latest`). Evidence: docs (Sidero "Local storage" guide and
`UserVolumeConfig` reference, v1.14), source (chart 0.0.37 pulled from the
OCI registry and its templates read; tag list read from ghcr.io), command
output (`talosctl get volumestatus` and `mountstatus` on the lab nodes,
2026-11-16), reference (onedr0p/home-ops uses Rook-Ceph, buroa/k8s-gitops
OpenEBS hostpath under `/var/mnt`).

## D36 Database details: OCI charts, the minimal image, the endpoint from a Secret

CloudNativePG 1.30.1 (chart `cloudnative-pg` 0.29.1) and the Barman Cloud
Plugin v0.16.0 (chart `plugin-barman-cloud` 0.9.0), both from
`oci://ghcr.io/cloudnative-pg/charts/`, so they fit the OCIRepository
layout of D32. Both run in `cnpg-system`: the plugin must share the
operator's namespace, and v0.16.0 needs operator 1.30 or newer, so the two
are upgraded together; Renovate marks minor and major updates of every
`cloudnative-pg` package as an upgrade drill. CloudNativePG 1.30 lists
Kubernetes 1.34 to 1.36 as supported and PostgreSQL 14 to 18; the image is
`ghcr.io/cloudnative-pg/postgresql:18.6-minimal-trixie`, over the
operator's default `18.6-system-trixie`: `system` is deprecated and exists
only to carry Barman, which now runs in the plugin's sidecar. Namespace
`database` enforces the `restricted` pod security level; CloudNativePG's
defaults match it, but its docs do not claim conformance, so this is
verified at the gate. The ObjectStore takes the endpoint from the
environment variable `AWS_ENDPOINT_URL_S3`, filled from the Secret, instead
of `endpointURL`: the endpoint carries the tenancy namespace and the
repository is public; path-style addressing as in D24, and the two
checksum variables at `when_required` as the plugin's "Object stores" page
documents. The sidecar reads its environment only when a pod is created
(plugin issue #918, open), so the ObjectStore is in place before the
Cluster. On retention, D24 stands and the test is moved forward: the
sidecar ships boto3 1.43.126 without `awscrt`, and boto3 computes CRC32C
only through the CRT, so no setting makes its multi-object delete use the
one checksum the store accepted. The test deletes one base backup with
`barman-cloud-backup-delete` inside the sidecar as soon as two backups
exist, instead of waiting a day for the retention policy; issue #770
(base backups not pruned, open) is a second reason to check the bucket and
not the plugin's status. Evidence: source (`Chart.yaml` of both charts
read from the OCI registry with `helm show chart`; the plugin's
`api/v1/objectstore_types.go`, `containers/sidecar-requirements.txt` and
CloudNativePG's `pkg/versions/versions.go` at the release tags), docs
(CloudNativePG supported releases, security, backup and recovery pages;
the plugin's installation, object stores and retention pages; the AWS SDK
data integrity reference), command output (the image tag answered 200
from ghcr.io, 2026-11-16), issues (plugin-barman-cloud #770, #918, #1049,
#1055).

## D37 Gate step 6 of phase 7 is split: the retention delete closes the gate, the plugin's own run is a follow-up

Owner's decision, 2026-11-16. The plugin cannot expire anything sooner than
a day: the ObjectStore accepts only `^[1-9][0-9]*[dwm]$`, and Barman's
recovery window keeps the newest backup that ended before the window start,
so a backup becomes obsolete only once a newer one is itself older than
the window. With one backup in the bucket on 2026-11-16, the earliest
plugin delete was about 2026-11-18 03:30 UTC. What step 6 was meant to
prove first, that the bucket accepts retention deletes of backups and WAL
(D24, D36), does not need the plugin's timer: `barman-cloud-backup-delete
-r "REDUNDANCY 2"` from the sidecar image (Barman 3.20.1) removed two
backups and WAL segments 1/7 to 2/B on 2026-11-16, through the per-object
fallback after `MissingContentMD5`, and a direct listing of the bucket
showed only the two kept backups and the WAL they need. That closes the
gate (step 6a). Whether the plugin's own run removes an expired backup
(issue #770: base backups not pruned, open) is step 6b, a follow-up that
does not hold phase 8. If it fails, the result is backups piling up in the
bucket, not lost data, and the fallback in D24 is applied in a small
change. Retention stays `1d` until 6b has been observed, then returns to
`7d` (D27). Evidence: command output (the Job and the listing in the
database guide, 2026-11-16), source (plugin v0.16.0
`internal/cnpgi/instance/retention.go`; Barman
`barman/retention_policies.py` as read at 3.12.1, while the sidecar runs
3.20.1), the CRD read from the cluster, issues
(plugin-barman-cloud #770, #1115).

## D38 Identity provider: Keycloak, installed by its own operator

The first application is Keycloak (26.8.2 when this was written), chosen
over authentik, ZITADEL, Kanidm, Ory, Authelia with LLDAP, Pocket ID,
Rauthy, Casdoor and Logto. The lab has two uses for an identity provider:
single sign-on for the owner's applications, and practice of enterprise
identity integration for databases and applications (LDAP and Active
Directory federation, Kerberos). Every candidate does OIDC; the second use
decides. Keycloak documents LDAP and Active Directory user federation and
a Kerberos bridge as standard features, is Apache-2.0 with no paid feature
tier, is a CNCF incubating project and is the base of Red Hat's commercial
build, so the skill carries over to enterprise environments.

authentik came closest: PostgreSQL only since 2025.10, Active Directory
and LDAP sources, and an LDAP outpost that a database could bind against.
It was not chosen because its Kerberos source is a preview, several
directory integrations need its enterprise licence, and enterprise
databases bind against Active Directory, which the lab will provide with a
directory server in a later phase in any case. ZITADEL has no LDAP server
and no Kerberos and moved to AGPL with v3; Kanidm keeps its state in an
embedded store outside CloudNativePG and has neither SAML nor Kerberos;
Ory keeps SAML in its enterprise edition and ships no login interface;
Authelia, Pocket ID and Rauthy lack SAML or directory federation; Casdoor
and Logto lack Kerberos. Keycloak is not a directory: LDAP, Kerberos and
Active Directory practice needs a directory server, which is a phase of
its own.

Installation: the official Keycloak Operator in single-namespace mode,
from the `keycloak-k8s-resources` kustomize resources at the release tag.
Rejected: the operator's Helm chart (documented as experimental), the
Bitnami chart (its images moved to an unmaintained legacy registry in
2025), codecentric's `keycloakx` chart (third party) and a plain
Deployment (an optimized start needs a custom image). One operator version
supports one Keycloak version; an upgrade sets the new image first, then
upgrades the operator. Deleting the operator's CRDs deletes every Keycloak
resource, so they are excluded from pruning. `KeycloakRealmImport` only
creates a realm and never updates one; how realm configuration is kept in
Git is decided when the first client is added. Evidence: docs (Keycloak
operator installation, basic deployment, advanced configuration, realm
import and sizing pages; the documentation and READMEs of every
candidate; all read 2026-11-16), judgment.

## D39 Application databases: one CloudNativePG cluster per application

Each application that needs PostgreSQL gets its own CloudNativePG cluster,
over one shared cluster with a database per application. The CloudNativePG
FAQ recommends one cluster per database. Recovery and major upgrades act
on a whole cluster: a point-in-time restore of a shared cluster rewinds
every application in it, and an in-place major upgrade stops them all at
once. Cluster `postgres` (D27) stays the drill target, and a drill on it
does not touch application data.

An application cluster is named `<app>-db` and lives in the application's
namespace, because the application reads the generated `<app>-db-app`
Secret and Secrets do not cross namespaces. Defaults: two instances with
pod anti-affinity, so that a node restart during a manual upgrade (D17)
fails over instead of stopping the application; 5 GiB per instance with WAL
on the same volume; image and plugin as in D36; its own `ObjectStore`
writing to `cnpg/<app>-db/` (D24); a daily base backup and WAL archiving,
retention as for `postgres` (D27, D37). A shared Flux component for this is
extracted when the second application needs one, not before. The cost is
one more set of PostgreSQL pods and one more WAL archive per application.
Application data in these clusters is backed up by D15; D16 still holds
for volumes. Evidence: docs (CloudNativePG FAQ, bootstrap and upgrade
pages, read 2026-11-16 on GitHub for `main` and `release-1.30`), judgment;
bjw-s-labs/home-ops runs one cluster per application in the same way.

## D40 Keycloak memory: 1 GiB requested, 2 GiB limit

The `Keycloak` resource sets a memory request of 1 GiB and a limit of 2
GiB, over the operator's default request of 1700 MiB with the same limit.
A few minutes after a restart, with realm `master` and realm `gate` from
the phase gate and no application sessions, Keycloak's working set was 564
MiB; a second read about seven minutes after start gave 536 MiB (kubelet
stats summary, 2026-11-17; the cluster has no metrics API). Keycloak gives
the JVM heap 70% of the container limit, and needs about 300 MB outside
the heap on top (sizing guide), so the limit is kept and the heap stays as
it was. The request drops so that one Keycloak does not reserve almost a
quarter of a node's 7.1 GiB allocatable memory. The sizing guide's 1250 MB
base per pod includes 10,000 cached sessions, which a lab will not reach,
so a request below it is intended. No CPU request or limit: the same stats
read showed 1.3 cores in use shortly after start and under 15 millicores
for the database and operator pods. Evidence: tested (kubelet stats
summary of `keycloak-0`, 2026-11-17), docs (Keycloak memory and CPU
sizing), the owner's approval on 2026-11-17.

## D41 Start page: Homepage with its own OIDC login against Keycloak realm `lab`

The start page is Homepage (gethomepage.dev), installed from plain
manifests in the shape of its Kubernetes installation page; there is no
official chart. It comes before monitoring, which becomes phase 10; where
earlier records say "phase 9" for monitoring, they mean that phase.

The login is Homepage's own: since version 2.0 it has a gate with a
password or OIDC, and with it on, every page and API route needs a
session except the health check. It signs in against a new Keycloak realm
`lab` with a confidential client `homepage`; realm `master` stays for
administration. Not chosen: an Envoy Gateway `SecurityPolicy` with OIDC
(an alpha API, and Envoy itself would have to reach the issuer) and
oauth2-proxy (one more Deployment). Either becomes the subject of a new
record when an application without its own login arrives. Homepage
checks no claims, so whoever can sign in to realm `lab` gets in; the
realm holds only user `owner`.

Realm `lab`, the client and the user are created by a `KeycloakRealmImport`
in Git, with the client secret and the password passed as placeholders from
a Secret. The operator imports only a realm that does not exist yet; a
later change to the resource does not change the realm, so changes after
the first import are made with `kcadm.sh` and written back into the
resource.

Evidence: docs (Homepage installation pages, "Security / Authentication",
read and checked 2026-11-17 for v2.8.0; Keycloak Operator realm import
page and the 26.8.2 source of the import Job; Envoy Gateway OIDC task for
v1.10), the owner's choice on 2026-11-17.

Outcome of the phase, 2026-11-17: Homepage runs with a read-only root file
system. It copies any file of `/app/src/skeleton` missing from
`/app/config` when `/api/validate` runs and exits when it cannot, so all
nine skeleton files of v2.8.0 are mounted from the ConfigMap; logs and the
Next.js cache are `emptyDir` volumes. Evidence: tested (the crash on the
cluster with eight files, reproduced and fixed with the same image under
Docker, then the phase gate).

## D42 Monitoring: victoria-metrics-k8s-stack, Prometheus-format scraping, OTLP later

One HelmRelease of `victoria-metrics-k8s-stack` in namespace
`observability`: the VictoriaMetrics operator, a single-node VMSingle, a
VMAgent that scrapes, kube-state-metrics, node-exporter and the chart's
Grafana with the kube-prometheus dashboards it ships. Metrics are scraped in
Prometheus format; nothing is collected through OpenTelemetry in this phase.

Over:
- `kube-prometheus-stack`, which both reference repositories run. Both cap
  Prometheus at a 4 GiB memory limit, twice the phase's budget of 2 GiB for
  the whole tool, and run Grafana separately through grafana-operator.
- An OpenTelemetry-native stack (`opentelemetry-kube-stack`). It installs
  the OpenTelemetry operator and a collector but no storage and no Grafana,
  so it is two tools. Nothing in the cluster emits OTLP today: CloudNativePG,
  the kubelet, kube-state-metrics and node-exporter all expose Prometheus
  metrics, and the dashboards for them expect Prometheus names, which the
  collector's own receivers (kubeletstats) do not produce.

Reason: VictoriaMetrics accepts OTLP metrics over HTTP (protobuf) at
`/opentelemetry/v1/metrics`, and VictoriaLogs and VictoriaTraces are opt-in
parts of the same chart, so OpenTelemetry is added later without replacing
the store: a collector writes OTLP into the same VMSingle. The owner's
`obenhub` project already uses an OpenTelemetry Collector with
VictoriaMetrics, VictoriaLogs and VictoriaTraces as its reference backend,
so queries, rules and dashboards can move between the two. Neither chart
publishes memory figures, so "lighter than Prometheus" is an assumption;
the gate measures it.

Scraping:
- CloudNativePG through a `VMPodScrape` written in Git: the Cluster field
  `spec.monitoring.enablePodMonitor` is deprecated, and the operator's
  conversion of Prometheus Operator resources needs their CRDs, which the
  VictoriaMetrics operator does not install. The conversion is turned off
  and those CRDs are not installed. A second `VMPodScrape` scrapes the
  CloudNativePG operator, whose metrics the dashboard's operator panels use.
- Talos: kube-proxy is not scraped (Cilium replaces it). etcd, the
  scheduler and the controller manager are not scraped in this phase: etcd
  serves metrics only after a machine config change (port 2381), and Talos
  documents no metrics endpoint for the other two. Each is a later change
  with its own record.

Evidence: docs (victoria-metrics-k8s-stack 0.98.1 Chart.yaml, values.yaml
and documentation page; VictoriaMetrics operator Prometheus integration and
OpenTelemetry ingestion pages; CloudNativePG monitoring page; Talos etcd
metrics page; opentelemetry-kube-stack 0.27.1 Chart.yaml; all read
2026-11-17), reference (buroa/home-ops and onedr0p/home-ops observability
HelmReleases, kube-prometheus-stack 93.3.1), the owner's `obenhub` ADR 0002,
judgment. The owner left the choice to the architect on 2026-11-17.

Settled while building, 2026-11-17:
- vmalert stays and evaluates the chart's recording and alerting rules,
  which the dashboards use; Alertmanager is off and vmalert runs with
  `-notifier.blackhole`, so alerts go nowhere until a receiver is chosen.
- VMSingle keeps 30 days in a 20 GiB volume (the chart's default size) on
  local-path; the data disk has 100 GiB per node.
- The release is named `vm`: the subcharts name their objects after the
  release, so Grafana's Service is `vm-grafana`.
- The VictoriaMetrics CRDs stay plain (the default, `crds.plain: true`):
  the operator chart's `crds` subchart carries them in its `crds/`
  directory; templated CRDs fail the first install, because Helm maps the
  VMAgent and VMSingle of the same release before any CRD exists (tested in
  a throwaway kind cluster, 2026-11-17). Flux upgrades them
  (`upgrade.crds: CreateReplace`), and the chart's uninstall hook that
  deletes them is off.
- Accepted: the chart's sync Job downloads the dashboards and rules from
  upstream `master` branches at every install and upgrade, so they are not
  pinned and the install needs GitHub. Pinning them would mean keeping
  copies in Git, which the lab does not need.

## D43 Grafana login: Grafana's own OIDC against Keycloak realm `lab`

Grafana signs in with its generic OAuth against
`https://keycloak.lab.savdert.com/realms/lab`, confidential client
`grafana`, in the pattern of D41: no proxy in front, and every user of
realm `lab` (only `owner`) gets the Grafana role Admin. The login form
stays for the local `admin` user as the way in when Keycloak is down; its
password and the client secret come from 1Password item `grafana` in vault
`homelab-cluster` through an `ExternalSecret`.

Realm `lab` exists, so the operator will not import it again (D41): the
client is created with `kcadm.sh` and written back into the
`KeycloakRealmImport`, so that a rebuilt cluster gets it.

Evidence: judgment (D41 left an application with its own login to its own
OIDC), docs to be read in phase 10 (Grafana generic OAuth for the pinned
version).
