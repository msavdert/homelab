# ADR-0008: `k3snet` — a private, NAT-isolated SDN network for cluster VMs

Date: 2026-08-02
Status: Accepted

## Context

ADR-0005 through ADR-0007 fixed the cluster's distribution (k3s), CNI
(Cilium), and GitOps controller (ArgoCD), but none of them fixed how the
cluster's VM(s) attach to the network. The host's only configured bridge,
`vmbr0`, carries the Hetzner-assigned public IP
(`88.99.150.113/26`) directly — it is not a private/internal bridge. Per
`CLAUDE.md`'s security baseline and `docs/PLAN.md`'s explicit out-of-scope
list ("public-facing services (Tailscale-only access by design)"), cluster
VMs must not end up with routable public IPs or inbound-open ports on the
public internet, the same way the Proxmox host itself has no public SSH
exposure and is only reached over Tailscale.

While investigating the host for this work, an existing Proxmox SDN
configuration was found already applied: a `simple` zone `localnat` with
two VNets, `k3snet` (10.0.1.0/24) and `vnet0` (10.0.0.0/24), both NAT'd
out through `vmbr0`. This predates the 2026-08-01 "clean slate" VM/CT wipe
recorded in `docs/PLAN.md` and was not created through Terraform or
documented anywhere in this repo — it's a manual leftover from an earlier
k3s experiment, created via the Proxmox UI (Datacenter > SDN) following
this general pattern:

1. Create a `simple` zone (`localnat`), DHCP backend `dnsmasq`, IPAM `pve`.
2. Create a VNet (`k3snet`) in that zone, with an alias for readability.
3. Create a subnet on the VNet: CIDR `10.0.1.0/24`, gateway `10.0.1.1`,
   SNAT enabled (egress NAT through `vmbr0`'s public IP), DHCP range
   `10.0.1.100`–`10.0.1.200`.
4. Apply the SDN configuration (`Datacenter > SDN > Apply`), which writes
   the zone/vnet as a real Linux bridge (`ip a show k3snet`) plus
   `iptables` SNAT/conntrack-zone rules on the host.

`vnet0` (10.0.0.0/24) is a second, unused leftover from the same era
(likely an earlier Talos experiment per ADR-0005's research) — left in
place for now (see Consequences) rather than deleted as part of this ADR,
since deleting it is an unrelated cleanup action, not required for
`k3snet` to work.

Also already in place: `pve` itself runs as a **Tailscale subnet router**
(`tailscale up --advertise-routes=...`), and the tailnet admin console
already shows both `10.0.0.0/24` and `10.0.1.0/24` as **Approved** routes
through it (machine `pve`, tailnet IP `100.121.170.22`). This was set up
by the operator for exactly this purpose and predates this ADR — it means
`k3snet` (`10.0.1.0/24`) is *already* reachable from any tailnet member
with route acceptance on, with no per-VM Tailscale install needed.

## Decision

Reuse **`k3snet`** as the network cluster VMs attach to, brought under
Terraform management (`infrastructure/terraform/network.tf`) via
`proxmox_sdn_zone_simple`, `proxmox_sdn_vnet`, and `proxmox_sdn_subnet`,
imported from the existing live config rather than recreated — recreating
would mean a real (if brief) network interruption for no benefit, since
the existing config already matches what this ADR would have specified
from scratch.

Network shape:

- Zone `localnat` (simple/NAT, `dnsmasq` DHCP, `pve` IPAM), node `pve`.
- VNet `k3snet` (alias `k3s-net`) in that zone.
- Subnet `10.0.1.0/24`, gateway `10.0.1.1`, SNAT enabled, DHCP range
  `10.0.1.100`–`10.0.1.200`.

Cluster VMs get a DHCP or static address in `10.0.1.0/24`, reach the
internet (package installs, pulling container images) via SNAT through the
host's public IP, and are **not** independently reachable from the public
internet — there is no inbound port-forward or public-bridge attachment.

Interactive/administrative access (SSH, `kubectl`) uses the **existing
`pve` Tailscale subnet router**, which already advertises and has
Approved-status for `10.0.1.0/24` in the tailnet admin console — cluster
VMs need no Tailscale client of their own. Any operator machine on the
tailnet with route acceptance on (`tailscale up --accept-routes`, the
default for most clients) reaches `10.0.1.x` directly, the same way `pve`
itself (`88.99.150.113`, no public SSH) is already reached at its tailnet
IP `100.121.170.22`. This was the operator's own prior setup, not new work
from this ADR — it's documented here because nothing in the repo
mentioned it before.

## Alternatives considered

- **Attach VMs directly to `vmbr0`.** Rejected outright — gives every
  cluster VM a routable public IP by default, violating the
  Tailscale-only access rule from `CLAUDE.md`/`docs/PLAN.md`. Would need
  host-level firewalling to claw back, as an afterthought, what a private
  bridge provides by construction.
- **Delete the leftover SDN config and rebuild an equivalent private
  network from scratch in Terraform.** Rejected for this ADR — the
  existing `k3snet` config is correct, already applied, and recreating it
  would cause a real (if brief) outage for VMs that don't exist yet
  anyway, for zero design benefit. Terraform `import` achieves the same
  "everything is code" outcome without the churn.
- **Tailscale installed inside every cluster VM**, instead of relying on
  the `pve` subnet router. Considered, but rejected as unnecessary and
  redundant: the subnet router path already exists, is already approved
  for `10.0.1.0/24`, and gives identical reachability with one fewer
  moving part per VM (no per-VM auth-key provisioning/rotation). The
  tradeoff is that a compromised VM sits on a subnet the router already
  exposes to the tailnet rather than having its own scoped identity — an
  accepted risk here given the tailnet itself is already the trust
  boundary for this whole project (same boundary the Proxmox host
  operates inside). Revisit if a later phase's threat model wants
  per-workload tailnet identity (e.g. Tailscale ACLs scoped to individual
  DB VMs) rather than blanket subnet access.

## Consequences

- `infrastructure/terraform/network.tf` now owns `localnat`/`k3snet`'s
  zone/VNet/subnet config; changes to DHCP range, SNAT, or gateway go
  through Terraform from here on, not the Proxmox UI.
- Cluster VM resources (Terraform clones of the Phase 0 template) attach
  their `network_device` to VNet `k3snet`, not `vmbr0`. No Tailscale
  provisioning step is needed per VM; they're reachable as soon as they
  have a `10.0.1.x` address, via the existing `pve` subnet route.
- `vnet0` (10.0.0.0/24) remains as an undocumented, unused leftover.
  Revisit and likely delete it once it's confirmed nothing depends on it
  — tracked as cleanup, not blocking.
- Cilium (ADR-0006) runs with `kube-proxy` replacement inside this private
  subnet; nothing about `k3snet` changes that decision, but Hubble/Cilium
  observability traffic stays within the NAT'd subnet, not exposed
  publicly either.
