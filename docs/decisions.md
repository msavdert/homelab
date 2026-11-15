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
