# homelab

A Kubernetes lab on a single Proxmox host. It has two uses: running the
owner's own applications, and practising database reliability work on
PostgreSQL (operations, backup, point-in-time recovery).

Three Talos Linux virtual machines form the cluster. Flux deploys what is in
this repository. Services are reachable from the tailnet and from guests on the Proxmox
host's `vnet0`, not from the internet. The data in
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

Phases 0 to 10 are finished and none is open: the nodes, the cluster, Flux,
secrets, ingress, storage, the first PostgreSQL cluster, Keycloak, the
Homepage start page and monitoring run. The
[Roadmap](roadmap.md) has the detail.

## Guides

A guide is added when its phase is finished and verified. They are listed
under "Guide" in the navigation:

- [00 Repository](guide/00-repository.md)
- [01 Nodes](guide/01-nodes.md)
- [02 Cluster](guide/02-cluster.md)
- [03 Flux](guide/03-flux.md)
- [04 Secrets](guide/04-secrets.md)
- [05 Ingress](guide/05-ingress.md)
- [06 Storage](guide/06-storage.md)
- [07 Database](guide/07-database.md)
- [08 Keycloak](guide/08-keycloak.md)
- [09 Homepage](guide/09-homepage.md)
- [10 Monitoring](guide/10-monitoring.md)
