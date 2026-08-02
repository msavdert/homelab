# The `localnat` SDN zone and `k3snet` VNet/subnet that k3s cluster VMs
# attach to. See ADR-0008 for why this network exists and why it's
# NAT-isolated from the host's public bridge (`vmbr0`) rather than bridged
# onto it directly.
#
# Both were originally created by hand via the Proxmox UI (Datacenter >
# SDN); this brings that existing, already-applied config under Terraform
# management rather than recreating it.
resource "proxmox_sdn_zone_simple" "localnat" {
  id    = "localnat"
  dhcp  = "dnsmasq"
  ipam  = "pve"
  nodes = [var.proxmox_node]
}

resource "proxmox_sdn_vnet" "k3snet" {
  id    = "k3snet"
  zone  = proxmox_sdn_zone_simple.localnat.id
  alias = "k3s-net"
}

resource "proxmox_sdn_subnet" "k3snet" {
  cidr    = "10.0.1.0/24"
  vnet    = proxmox_sdn_vnet.k3snet.id
  gateway = "10.0.1.1"
  snat    = true

  dhcp_range = {
    start_address = "10.0.1.100"
    end_address   = "10.0.1.200"
  }
}
