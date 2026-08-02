# Project Plan

Phased roadmap for the homelab rebuild. Order reflects "DBRE-first,
Kubernetes-second": the platform (Phase 0-1) exists to run the databases
(Phase 2 onward), which is where most of the depth and documentation should
go.

Check off items as they land, and open an ADR in
[`decisions/`](decisions/) for any non-trivial choice made along the way —
this file tracks *what's done*, ADRs track *why it was done that way*.

## Status: Phase 0 in progress

Last updated: 2026-08-01.

---

## Phase 0 — Foundation

Goal: a clean, code-provisioned base to build on.

- [x] Proxmox VE 9 installed on ZFS mirror (documented externally, see README)
- [x] Tailscale mesh between operator machines and the Proxmox host
- [x] Wiped all leftover test VMs/CTs (CKA cluster, k3s cluster, Oracle
      DB/GoldenGate VMs, hermes-agent LXC) — clean slate, 2026-08-01
- [x] `infrastructure/terraform/` — Proxmox provider, VM/CT provisioning as
      code, fully automated end to end (no manual steps) — see
      [ADR-0004](decisions/0004-root-pam-terraform-token.md) for the Proxmox
      API token quirk this required working around
- [x] Debian 12 cloud-init template re-applied on the live host (VM ID 9000,
      node `pve`) on 2026-08-01, rebuilt from the new VPS dev machine after
      state was deliberately `terraform destroy`'d as part of moving the
      development environment from the operator's Mac to a persistent VPS
      session (Claude Code + zellij) — trivial to rebuild since Phase 0 had
      no other resources depending on it yet
- [x] Base OS image/template strategy — [ADR-0002](decisions/0002-cloud-init-vm-template.md):
      Debian 12 cloud-init image, cloned per VM
- [x] Secrets management backend chosen — [ADR-0003](decisions/0003-sops-age-secrets.md):
      SOPS + age

## Phase 1 — Kubernetes platform (secondary learning goal)

Goal: a working, GitOps-managed cluster to run database workloads on. Look
at patterns from popular starred OSS homelab repos before locking in
choices; this phase is deliberately a learning track, not just plumbing.

- [ ] Cluster distribution decision (Talos / k3s / kubeadm) — needs an ADR
- [ ] CNI choice
- [ ] GitOps tool + sync strategy (ArgoCD ApplicationSets vs. Flux, etc.)
- [ ] Ingress + TLS
- [ ] Base observability: Prometheus + Grafana + Loki

## Phase 2 — Database reliability core (the point of this project)

Goal: real, observable, drillable database reliability engineering. Each
sub-item should end with a runbook in `docs/runbooks/`.

- [ ] PostgreSQL with HA (operator TBD — CloudNativePG vs. Patroni) — ADR
- [ ] MySQL/MariaDB with HA (Group Replication / Percona XtraDB / Vitess) — ADR
- [ ] Automated backups + WAL/binlog archiving to durable storage (e.g. MinIO)
- [ ] Point-in-time recovery: proven with an actual drill, documented
- [ ] Failover: proven with an actual induced-failure drill, documented
- [ ] Connection pooling (PgBouncer / ProxySQL) and what it changes under load
- [ ] DB-specific monitoring: replication lag, connection saturation, WAL
      growth, slow queries — dashboards + alerting
- [ ] Load testing (pgbench / sysbench) to validate the above under stress

## Phase 3 — Chaos & reliability validation

Goal: don't just claim reliability, break things on purpose and show the
recovery.

- [ ] Chaos tooling in the cluster (Chaos Mesh or similar)
- [ ] At least one documented "game day": induced failure, response,
      postmortem-style writeup

## Phase 4 — Polish for the portfolio

- [ ] Architecture diagrams
- [ ] Consolidated runbook index
- [ ] Top-level write-up tying the whole system back to DBRE competencies

---

## Explicitly out of scope (for now)

Keep this section updated — it prevents scope creep and gives future-me (or
an interviewer) a clear read on what was deliberately deferred vs. missed.

- Multi-site / disaster-recovery-across-datacenters (single Hetzner host)
- Public-facing services (Tailscale-only access by design)
