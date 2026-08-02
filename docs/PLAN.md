# Project Plan

Phased roadmap for the homelab rebuild. Order reflects "DBRE-first,
Kubernetes-second": the platform (Phase 0-1) exists to run the databases
(Phase 2 onward), which is where most of the depth and documentation should
go.

Check off items as they land, and open an ADR in
[`decisions/`](decisions/) for any non-trivial choice made along the way —
this file tracks *what's done*, ADRs track *why it was done that way*.

## Status: Phase 1 in progress

Last updated: 2026-08-02.

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

- [x] Cluster distribution decision (Talos / k3s / kubeadm) — [ADR-0005](decisions/0005-k3s-cluster-distribution.md):
      k3s on Debian 12 VMs
- [x] CNI choice — [ADR-0006](decisions/0006-cilium-cni.md): Cilium
      (kube-proxy replacement, Hubble observability)
- [x] GitOps tool + sync strategy — [ADR-0007](decisions/0007-argocd-gitops.md):
      ArgoCD, App-of-Apps to start, `ApplicationSet` deferred to Phase 2
- [x] k3s installed on `k3s-node-01` (v1.36.2+k3s1, single control-plane
      with embedded etcd via `--cluster-init` so additional server nodes can
      join later; Flannel/Traefik/ServiceLB disabled since Cilium and
      ArgoCD-managed ingress replace them per ADR-0006/ADR-0007) — node is
      `NotReady` until Cilium is deployed, expected with no CNI
- [x] Cilium CNI actually deployed to the cluster (ADR-0006) — Helm v3.21.3
      installed on `k3s-node-01`, Cilium chart `1.19.6` (latest patch of the
      most recently matured minor line at install time, deliberately
      avoiding the just-cut `1.20.0` for a day-0 bootstrap step) via
      `helm install cilium cilium/cilium --version 1.19.6 -n kube-system`
      with `kubeProxyReplacement=true`, `operator.replicas=1`,
      `hubble.enabled=true`, `hubble.relay.enabled=true`, and
      `hubble.ui.enabled=true`; node went `Ready` and coredns/
      local-path-provisioner/metrics-server all reached `Running`, verified
      via `cilium status` (`KubeProxyReplacement: True`, `Hubble: Ok`)
- [x] ArgoCD actually deployed to the cluster (ADR-0007) — Helm chart
      `argo/argo-cd` `10.2.2` (app `v3.4.6`; the just-cut `v3.5.0` was still
      RC-only at install time, so not used) installed via
      `helm install argocd argo/argo-cd --version 10.2.2 -n argocd
      --create-namespace -f gitops/argocd/values.yaml`; all pods
      `Running`. App-of-Apps bootstrapped per ADR-0007: `gitops/root-app.yaml`
      applied manually once, pointing at `gitops/apps/`, which contains
      `argocd.yaml` — ArgoCD's own self-referencing Application (multi-source:
      the `argo-cd` chart + this repo's `gitops/argocd/values.yaml`) — so
      ArgoCD now manages its own subsequent upgrades via GitOps
      ("day-0 manual, day-2 GitOps-managed"). Both `argocd` and `root-app`
      Applications show `Synced`/`Healthy`. No ingress/TLS yet — UI reachable
      via `kubectl -n argocd port-forward svc/argocd-server 8080:443`. KSOPS
      CMP integration (ADR-0007 consequence) still pending, needed before any
      SOPS-encrypted manifest can be synced.
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
