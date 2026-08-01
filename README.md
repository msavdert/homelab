# Homelab: A Database Reliability Engineering Portfolio

This repository documents the design, build, and operation of a homelab whose
primary purpose is **demonstrating Database Reliability Engineering (DBRE)
skills**: high availability, backup/restore, failover, replication,
monitoring, and incident response for production-grade database systems.

Kubernetes and GitOps are used as the delivery platform underneath the
databases — a secondary, explicit learning goal — but the project's center of
gravity is *the databases and how they stay reliable*, not the platform
itself.

## Why this repository exists

I'm transitioning my career toward Database Reliability Engineering. Rather
than a resume line, this is a working system: real failovers, real backups
restored under time pressure, real monitoring dashboards, real runbooks
written after real incidents (including ones I caused on purpose). Every
non-trivial decision is recorded in [`docs/decisions/`](docs/decisions/) with
its reasoning, not just its outcome.

## Infrastructure

| Layer | Choice | Notes |
| :--- | :--- | :--- |
| **Physical host** | Hetzner dedicated server (AX-class) | 12 cores / 128 GB RAM |
| **Hypervisor** | Proxmox VE 9, ZFS mirror root | Install documented in [this post](https://msavdert.github.io/posts/proxmox-9-hetzner-zfs-guide/) |
| **Private network** | Tailscale | Mesh VPN between the server and the operator's machines; no public SSH exposure |
| **Provisioning** | Terraform (Proxmox provider) | VMs and base config are code, not clicks |
| **Kubernetes** | TBD in [ADR-0002](docs/decisions/) | Secondary learning track |
| **GitOps** | TBD | ApplicationSet-style, informed by patterns in popular OSS homelab repos |

See [`docs/PLAN.md`](docs/PLAN.md) for the phased build roadmap and current
status, and [`docs/decisions/`](docs/decisions/) for the full log of
architectural decisions and their reasoning.

## Repository layout

```text
.
├── CLAUDE.md               # Ground rules for AI-assisted work in this repo
├── docs/
│   ├── PLAN.md              # Phased roadmap and current status
│   ├── decisions/           # ADRs — every non-trivial choice, with why
│   ├── architecture/        # Diagrams and system design docs (added as built)
│   └── runbooks/            # Incident-response procedures (added as built)
├── infrastructure/          # Terraform + Ansible (added in Phase 0)
└── kubernetes/              # Cluster manifests / GitOps (added in Phase 1)
```

Directories are created as each phase is actually implemented — this repo
does not carry placeholder scaffolding for work that hasn't happened yet.

## Status

Fresh rebuild started 2026-08-01. See [`docs/PLAN.md`](docs/PLAN.md) for
current phase and progress.
