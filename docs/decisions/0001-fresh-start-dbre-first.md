# ADR-0001: Fresh rebuild, DBRE-first / Kubernetes-second

Date: 2026-08-01
Status: Accepted

## Context

A prior homelab attempt (`homelab_backup`) built a general
platform-engineering stack — Proxmox + Talos + Cilium + Longhorn + ArgoCD
(ApplicationSets) + External Secrets/Infisical + Renovate. It's a reasonable
platform-engineering portfolio, but the operator is transitioning career
direction toward **Database Reliability Engineering (DBRE)**, and a generic
platform repo doesn't demonstrate that specific skill set to a hiring
manager.

The Proxmox host also accumulated leftover test VMs/CTs from unrelated
experiments (a CKA study cluster, a k3s cluster, Oracle DB + GoldenGate
VMs, an LXC container) that weren't part of any coherent design.

## Decision

Start a new repository (`homelab`, replacing `homelab_backup` as the active
project) with an explicit priority order: **database reliability
engineering first, Kubernetes/GitOps second.** Kubernetes remains a real
learning goal — including studying patterns from popular starred OSS
homelab repos — but it exists to host and demonstrate database HA, backup/
restore, failover, and monitoring work, not as the headline.

The Proxmox host was wiped clean (all VMs, CTs, and templates destroyed;
ZFS pool usage returned to ~9 GB) on 2026-08-01 to remove undocumented,
unrelated leftovers before building anything new.

## Alternatives considered

- **Rebuild the same general platform stack, just cleaner.** Rejected —
  doesn't differentiate for a DBRE-focused job search.
- **VM-first databases with Kubernetes only for peripheral tooling.**
  Not chosen as the default, but not ruled out either — some database
  workloads may still run as VMs directly on Proxmox where that better
  demonstrates OS-level DBA skills (WAL shipping, filesystem-level backups,
  kernel/IO tuning). That choice will be made per-database in Phase 2, with
  its own ADR if it happens.

## Consequences

- Every phase and ADR going forward should be evaluated against "does this
  demonstrate DBRE competency" before "is this the trendiest platform
  choice."
- The repo carries no legacy scaffolding from `homelab_backup` — anything
  reused from it is a deliberate, re-evaluated choice, not a carry-over.
