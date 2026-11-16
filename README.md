# homelab

[![Docs](https://img.shields.io/badge/docs-msavdert.github.io%2Fhomelab-blue)](https://msavdert.github.io/homelab/)
[![Release](https://img.shields.io/github/v/release/msavdert/homelab)](https://github.com/msavdert/homelab/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A Kubernetes lab on a single Proxmox host, built for two things:

- running my own applications;
- practising database reliability work on PostgreSQL: operations, backups
  and point-in-time recovery drills.

The lab is built one phase at a time. A phase is finished only when its
gate commands pass on the real cluster, and each finished phase gets a
step-by-step guide that can be repeated from scratch.

## Stack

| Layer | Component |
|---|---|
| Virtual machines | Proxmox VE, provisioned with OpenTofu |
| Node OS | Talos Linux, three nodes |
| Network | Cilium (no kube-proxy, layer-2 load balancer addresses) |
| GitOps | Flux, through the Flux Operator, following `main` |
| Secrets | External Secrets Operator reading 1Password |
| Certificates | cert-manager, Let's Encrypt DNS-01 through Cloudflare |
| Ingress | Envoy Gateway (Gateway API), reachable only over Tailscale |
| Storage | local-path-provisioner on a dedicated data disk per node |
| Databases | CloudNativePG, backups to S3-compatible object storage |
| Updates | Renovate and release-please |

Exact versions are pinned where they are used and kept current by Renovate.

## Status

| Phase | | Guide |
|---|---|---|
| 0 Repository foundation | done | [Repository](https://msavdert.github.io/homelab/guide/00-repository/) |
| 1 Nodes | done | [Nodes](https://msavdert.github.io/homelab/guide/01-nodes/) |
| 2 Cluster | done | [Cluster](https://msavdert.github.io/homelab/guide/02-cluster/) |
| 3 Flux | done | [Flux](https://msavdert.github.io/homelab/guide/03-flux/) |
| 4 Secrets | done | [Secrets](https://msavdert.github.io/homelab/guide/04-secrets/) |
| 5 Ingress | done | [Ingress](https://msavdert.github.io/homelab/guide/05-ingress/) |
| 6 Storage | done | [Storage](https://msavdert.github.io/homelab/guide/06-storage/) |
| 7 First database | in progress | |
| 8 First application | planned | |
| 9 Monitoring | planned | |

The [roadmap](docs/roadmap.md) has the gate of every phase.

## How it fits together

1. OpenTofu creates the node VMs inside a dedicated Proxmox pool, with a
   token that cannot touch anything outside it.
2. Talos is configured from patch files in `talos/`; Cilium is installed
   once at bootstrap.
3. Flux takes over from there and reconciles `kubernetes/apps/` from `main`.
   A merged pull request is a deployment.
4. No secret value lives in this repository. Files hold `op://` references,
   resolved per command on the workstation and by External Secrets in the
   cluster.

## Repository layout

```
infra/        OpenTofu for the node VMs; host preparation and DNS scripts
talos/        Talos machine configuration patches and node definitions
bootstrap/    one-time steps before Flux takes over
kubernetes/   everything Flux deploys, one directory per namespace
docs/         the documentation site, including the guides
```

## Documentation

The full documentation is at <https://msavdert.github.io/homelab/>:

- [Architecture](docs/architecture.md): what the lab consists of
- [Decisions](docs/decisions.md): why it is built this way, with evidence
- [Roadmap](docs/roadmap.md): what is built and what comes next
- [Host](docs/host.md): what the lab owns on the Proxmox host

Much of the work is done with AI coding agents; their rules are in
[AGENTS.md](AGENTS.md).

## Contributing

This is a personal lab, so pull requests are not accepted. Issues and
questions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
