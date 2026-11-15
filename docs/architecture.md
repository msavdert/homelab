# Architecture

What the lab is made of and how the parts connect. The reasons are in
[Decisions](decisions.md); what is built so far is in [Roadmap](roadmap.md).
A layer that is not built yet is described here as designed, and its
roadmap phase says so.

## The host

One rented server running Proxmox VE 9.2 (node name `pve`): Intel i7-8700
(6 cores, 12 threads), 126 GiB RAM, two 954 GiB NVMe disks in one ZFS pool
(`rpool`, striped, no redundancy). The host has one public IPv4 address on
bridge `vmbr0` and is a member of the owner's Tailscale network.

The host also runs guests that are not part of this lab (Oracle and
PostgreSQL practice machines and the agent box this repository is worked
from). They sit on VNet `vnet0`, 10.0.0.0/24. The lab never touches them.
See [Host](host.md) for the objects that belong to the lab.

## Network

```
internet ── vmbr0 (public address) ── Proxmox host ──┬── vnet0  10.0.0.0/24  other guests, agent box (10.0.0.11)
                                         SNAT        └── k8s    10.0.6.0/24  the lab
```

Both VNets are in the SDN zone `localnat` (type simple). The host is the
gateway of each (`.1`) and translates outgoing traffic to its public
address. Nothing on either VNet is reachable from the internet. The agent
box reaches the lab subnet through the host gateway.

The host is also a Tailscale subnet router (device `pve`). It advertises
10.0.0.0/24 and 10.0.6.0/24 to the owner's tailnet, and the tailnet policy
lets members reach both (read from the Tailscale API on 2026-11-15). That
is how the owner's devices reach the lab. The agent box is not on the
tailnet and does not need to be.

Address plan for 10.0.6.0/24:

| Address | Use |
|---|---|
| 10.0.6.1 | gateway (the host) |
| 10.0.6.10 | Kubernetes API virtual IP |
| 10.0.6.11 to 10.0.6.13 | nodes `k8s-1` to `k8s-3` |
| 10.0.6.20 to 10.0.6.29 | load-balancer addresses announced by Cilium; 10.0.6.20 is the gateway |
| 10.0.6.200 to 10.0.6.250 | DHCP range of the VNet; unused by the lab |

Inside the cluster the Talos defaults apply: pods 10.244.0.0/16, services
10.96.0.0/12. Neither overlaps the VNets.

Nodes use the resolvers 1.1.1.1 and 9.9.9.9. The host's own resolver is the
Tailscale one and is not reachable from guests, so it must not be inherited.

## Nodes

Three identical virtual machines in Proxmox pool `homelab`, each a Talos
control-plane node that also runs workloads.

| | |
|---|---|
| VM IDs and names | 201 `k8s-1`, 202 `k8s-2`, 203 `k8s-3` |
| CPU and memory | 2 vCPU (type `host`), 8 GiB, no ballooning |
| Firmware | OVMF, machine `q35`, 4 MB EFI disk without pre-enrolled keys |
| Disk controller | VirtIO SCSI (`virtio-scsi-pci`, not "single") |
| `scsi0` | 20 GiB system disk, imported from the Talos image; `/dev/sda` |
| `scsi1` | 100 GiB data disk for persistent volumes; `/dev/sdb` |
| Network | one VirtIO NIC on bridge `k8s`, static address from cloud-init |
| Guest agent | enabled (the image carries `siderolabs/qemu-guest-agent`) |

The VMs are created by OpenTofu in `infra/` with the bpg/proxmox provider.
Someone with other infrastructure skips `infra/` and starts from "three
Talos nodes answer in maintenance mode".

## Cluster

| Layer | Component | Notes |
|---|---|---|
| Node OS | Talos Linux | machine config from patch files in `talos/` |
| API endpoint | `https://10.0.6.10:6443` | Talos layer-2 virtual IP |
| CNI | Cilium | replaces kube-proxy; installed at bootstrap |
| GitOps | Flux Operator and one FluxInstance | pulls this public repository |
| Secrets | External Secrets Operator | 1Password SDK provider, vault `homelab-cluster`, read-only |
| Certificates | cert-manager | Let's Encrypt, DNS-01 through Cloudflare |
| Ingress | Envoy Gateway (Gateway API) | address from Cilium LB-IPAM, announced on the VNet |
| Storage | local-path-provisioner | volumes on each node's data disk |
| Object storage | bucket `homelab` (Oracle, S3-compatible) | `tofu/` state, `cnpg/` backups |
| Databases | CloudNativePG | backups to an S3-compatible bucket |
| Updates | Renovate | hosted GitHub app; opens pull requests |

Left out on purpose: replicated storage (Rook-Ceph, Longhorn), a service
mesh, Multus, Spegel, Cloudflare tunnels. Monitoring comes last, as one
tool.

## How a request reaches a service

This is the design for phase 5; none of it exists yet.

1. A device on the tailnet resolves `app.lab.savdert.com`. The public
   wildcard record `*.lab.savdert.com` returns 10.0.6.20, a private
   address.
2. The device's Tailscale client routes 10.0.6.0/24 to the subnet router
   `pve`, which is the Proxmox host and the gateway of the VNet.
3. 10.0.6.20 belongs to the Envoy Gateway Service. Cilium assigns it from
   its load-balancer pool and answers ARP for it on the VNet.
4. Envoy terminates TLS with the wildcard certificate and routes by
   `HTTPRoute`.

A device that is not on the tailnet resolves the name but has no route to
the address. There is no Tailscale component inside the cluster.

## Secrets

Values live in 1Password and are never written to the repository. There
are three vaults and three service accounts, so that the cluster can read
only what the cluster needs (D25):

| Vault | Holds | Read by |
|---|---|---|
| `dotfiles` | the owner's general secrets | the workstation's own service account |
| `homelab` | what builds and operates the lab from the workstation | a read-write service account whose token is in `dotfiles` |
| `homelab-cluster` | what workloads in the cluster need | a read-only service account used by External Secrets |

A task that needs vault `homelab` runs `op` with that vault's token for
the one command. Everything OpenTofu needs is in `homelab`, so a single
`op run` is enough.

| Item (vault `homelab` unless noted) | Fields | Used by |
|---|---|---|
| `proxmox-tofu` | `username` (token ID), `credential` | OpenTofu |
| `tofu-state` | `password` (the state encryption passphrase; exists) | OpenTofu state encryption |
| `object-storage` | `access-key`, `secret-key`, `endpoint`, `region`, `bucket` | OpenTofu state backend (exists; this key reaches every bucket of the account) |
| `eso-service-account` | `credential` (token of the read-only account for vault `homelab-cluster`) | applied once at bootstrap for External Secrets |
| `talos` | `secrets` (the whole `talosctl gen secrets` file, D30) | machine config rendering |
| `cloudflare-dns` | `credential` (token limited to DNS edit on savdert.com) | the `dns:apply` task |
| `cloudflare-dns` (vault `homelab-cluster`) | `credential` (same token) | cert-manager |
| `object-storage` (vault `homelab-cluster`) | as above, but a key limited to bucket `homelab` | CloudNativePG backups |
| `homelab-op-service-account` (vault `dotfiles`) | `credential` | tasks that read or write vault `homelab`; never given to the cluster |
| `Proxmox API` (vault `dotfiles`) | `username`, `credential` | the administrator token; `infra/host/prepare.py` only |
| `tailscale-oauth-readonly` (vault `dotfiles`) | `client-id`, `credential` | reading the tailnet policy and routes to check the owner's steps |

An item is created in the phase that first needs it. In vault `homelab`,
`proxmox-tofu`, `tofu-state`, `object-storage` and `cloudflare-dns` exist
and were checked on 2026-11-15. Vault `homelab-cluster` and its service
account do not exist yet; the owner creates them before phase 4.

## Repository layout

```
AGENTS.md            rules for agents
docs/                this documentation (published to GitHub Pages)
infra/host/          one-time host preparation (administrator token)
infra/               OpenTofu: the three VMs                        phase 1
talos/               machine config patches, image schematic        phase 2
bootstrap/           what is installed before Flux takes over       phase 2 to 4
kubernetes/          everything Flux reconciles                     phase 2 (Cilium files), then phase 3 onward
.claude/             agent definitions and session settings
mise.toml            tool versions and tasks                        phase 0
```

A directory appears when its phase is built.
