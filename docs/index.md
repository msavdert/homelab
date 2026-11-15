# homelab

A Kubernetes lab on a single Proxmox host. It has two uses: running the
owner's own applications, and practising database reliability work on
PostgreSQL (operations, backup, point-in-time recovery).

Three Talos Linux virtual machines form the cluster. Flux deploys what is in
this repository. Services are meant to be reachable only over Tailscale. The data in
the lab is disposable; the procedures are what matter.

## Where to read

| If you want to | Read |
|---|---|
| understand what the lab consists of | [Architecture](architecture.md) |
| know why it is built this way | [Decisions](decisions.md) |
| see what is built and what comes next | [Roadmap](roadmap.md) |
| know what the lab owns on the Proxmox host | [Host](host.md) |
| rebuild a layer step by step | the guides, one per finished phase |
| work on the repository | [Standards](standards.md) and [Handoff](handoff.md) |

## State

The host is prepared. No cluster exists yet. The roadmap has the detail.

## Guides

A guide is added when its phase is finished and verified. None yet.
