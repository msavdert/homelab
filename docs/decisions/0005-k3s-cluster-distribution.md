# ADR-0005: k3s (on Debian VMs) as the Kubernetes distribution

Date: 2026-08-01
Status: Accepted

## Context

Phase 1 needs a Kubernetes distribution to run on top of the Terraform/
Proxmox VM layer from Phase 0. Per `CLAUDE.md`, Kubernetes here is a
secondary, delivery-mechanism learning goal — the primary deliverable is
DBRE depth (Postgres/MySQL HA, backup/restore, failover drills,
monitoring) on top of it. "When a design choice trades off platform
elegance against database-reliability clarity, prefer the latter" is the
explicit tie-breaker for this whole phase.

Three options were on the table: Talos Linux, k3s, and kubeadm (vanilla).
Research into current, well-maintained public homelab repos (see task
notes) found:

- **Talos** is the emerging default in "serious" GitOps homelab repos
  (`mitchross/talos-argocd-proxmox`, `erwinkersten/homelab`,
  `ravilushqa/homelab`), often paired with CloudNativePG specifically.
  It's immutable and API-managed — no SSH, no shell, config via
  `talosctl` and machine-config YAML. Storage operators need explicit,
  somewhat undocumented handling: Longhorn requires system extensions
  (`iscsi-tools`, `util-linux-tools`) baked into the installer image plus
  a bind mount for its data dir; Rook-Ceph needs extra handling for
  `/etc/ceph` under the immutable root.
- **k3s** on a plain Debian VM is the older, still very common pattern
  (`pablodelarco/kubernetes-homelab`, `mortylabs/kubernetes`,
  `adamkoro/k3s-terraform-ansible`), almost always paired with Longhorn,
  which is well-documented for k3s specifically with no distro-specific
  extension gymnastics — just standard Debian packages
  (`open-iscsi`, `nfs-common`).
- **kubeadm** is rare in curated homelab repos; it shows up mainly in
  "learn Kubernetes the hard way" / exam-prep contexts, not GitOps-driven
  homelabs, because of the manual overhead of owning CNI, CSI, and
  control-plane component config directly.

All three integrate with ArgoCD/Flux identically, and all three can grow
from one VM to a multi-node VM cluster on the same Proxmox host without
architectural rework.

## Decision

Run **k3s on Debian 12 VMs** (the same cloud-init template from
ADR-0002), provisioned via the existing Terraform/Proxmox layer.

The deciding factor is debugging clarity for the actual point of this
project. Phase 2's DBRE work depends on being able to reach down to the
host when a database failover, replication lag spike, or storage issue
needs root-causing — standard SSH, systemd, `journalctl`, disk/network
tooling, no `talosctl`-mediated indirection and no immutable-root
workarounds to reason about first. Talos's storage-operator friction
(extensions, bind mounts) is exactly the kind of Kubernetes-layer
complexity that competes with, rather than serves, DB-reliability
learning time — it's real operational hardening, but it's platform
elegance, and this phase's tie-breaker rule points the other way.
kubeadm was rejected for the opposite reason: its manual control-plane
overhead is Kubernetes-internals learning, not DBRE learning, and this
project already has a secondary (not primary) budget for K8s depth.

## Alternatives considered

- **Talos Linux.** Rejected — strong platform (immutable, atomic
  upgrades, currently the more common choice in "serious" GitOps homelab
  repos) but the no-shell/no-SSH design and storage-operator extension
  requirements work against fast host-level diagnosis of database
  failures, which is the actual deliverable here. Worth revisiting if a
  later phase's threat model or multi-node growth makes immutability's
  security payoff outweigh the debugging cost.
- **kubeadm (vanilla).** Rejected — highest operational overhead
  (etcd, cert rotation, CNI/CSI wiring, upgrades all manual), and the
  overhead buys Kubernetes-internals depth this project doesn't need
  more of, at the cost of time better spent on Phase 2.
- **k3s with embedded storage add-ons left at defaults** (Traefik,
  ServiceLB, `local-path-provisioner`). Not fully rejected yet — ingress
  and storage choices are separate open Phase 1 items; this ADR only
  fixes the distribution.

## Consequences

- Cluster nodes are k3s on Debian 12, using the existing cloud-init
  template and Terraform VM provisioning — no new base-image work
  needed.
- Longhorn is the expected storage-operator path for Phase 2's
  StatefulSets (CloudNativePG/Patroni, MySQL/MariaDB); the CNI and
  ingress/TLS items later in Phase 1 should be evaluated with k3s's
  defaults (Traefik, ServiceLB, Flannel) as the baseline to keep or
  replace, not assumed.
- Multi-node growth later (if pursued) uses k3s's server/agent join
  tokens against additional Terraform-provisioned VMs on the same
  Proxmox host — no re-architecture required.
- Revisit if host-level immutability/security hardening becomes a
  stated project goal in a later phase — Talos remains the documented
  alternative here rather than a closed question.
