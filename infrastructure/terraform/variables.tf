

# =============================================================================
# Proxmox
# =============================================================================

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint (e.g. https://proxmox:8006/)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token (e.g. root@pam!token=uuid)"
  type        = string
  sensitive   = true
}

variable "proxmox_target_node" {
  description = "Proxmox target node name. Run 'pvesh get /nodes' to find it."
  type        = string
}

variable "proxmox_iso_storage" {
  description = "Proxmox storage pool name for ISO images. Run 'pvesh get /nodes/<NODE>/storage' to find it. Typically 'local'."
  type        = string
  default     = "local"
}

variable "proxmox_vm_storage" {
  description = "Proxmox storage pool name for VM disks. Run 'pvesh get /nodes/<NODE>/storage' to find it. Typically 'local-zfs' or 'local-lvm'."
  type        = string
  default     = "local-zfs"
}

variable "proxmox_network_bridge" {
  description = "Network bridge for VMs (e.g. vmbr0, vnet0). Run 'pvesh get /cluster/sdn/vnets' to find it."
  type        = string
  default     = "vnet0"
}

# =============================================================================
# Talos Linux
# =============================================================================

variable "talos_version" {
  description = "Talos Linux version to install. See: https://github.com/siderolabs/talos/releases"
  type        = string
  default     = "1.13.0"
}

variable "kubernetes_version" {
  description = "Kubernetes version to deploy. Must be compatible with the chosen Talos version."
  type        = string
  default     = "1.36.0"
}

variable "talos_linux_iso_image_url" {
  description = "URL of the Talos nocloud ISO image for initial VM boot. Generate at https://factory.talos.dev"
  type        = string
  default     = "https://factory.talos.dev/image/a7bcadbc1b6d03c0e687be3a5d9789ef7113362a6a1a038653dfd16283a92b6b/v1.13.0/nocloud-amd64.iso"
}

variable "talos_linux_iso_image_filename" {
  description = "Filename used when storing the Talos ISO in Proxmox storage."
  type        = string
  default     = "talos-linux-v1.13.0-nocloud-amd64.iso"
}

# =============================================================================
# Cluster
# =============================================================================

variable "cluster_name" {
  description = "Name for the Talos cluster."
  type        = string
  default     = "talos"
}

variable "cluster_vip_shared_ip" {
  description = "Virtual IP shared across control plane nodes for a highly available API server endpoint."
  type        = string
  default     = "10.0.0.9"
}

variable "node_data" {
  description = <<-EOT
    Map of node IP addresses to their configuration.
    The IP address is used as the map key and is assigned statically via nocloud.
    'install_disk' is the target disk for Talos installation (e.g. /dev/sda).
    'hostname' is optional; defaults to '<cluster_name>-cp-<index>' or '<cluster_name>-worker-<index>'.

    Note: 'install_image' is reserved for future per-node image overrides and is currently unused;
    the schematic-based image URL from talos_image_factory_urls is used for all nodes.
  EOT
  type = object({
    controlplanes = map(object({
      install_disk  = string
      install_image = string
      hostname      = optional(string)
    }))
    workers = map(object({
      install_disk  = string
      install_image = string
      hostname      = optional(string)
    }))
  })
  default = {
    controlplanes = {
      "10.0.0.10" = {
        install_disk  = "/dev/sda"
        install_image = ""
      }
    }
    workers = {
      "10.0.0.11" = {
        install_disk  = "/dev/sda"
        install_image = ""
      }
      "10.0.0.12" = {
        install_disk  = "/dev/sda"
        install_image = ""
      }
      "10.0.0.13" = {
        install_disk  = "/dev/sda"
        install_image = ""
      }
      "10.0.0.14" = {
        install_disk  = "/dev/sda"
        install_image = ""
      }
    }
  }
}

variable "network" {
  description = "CIDR block for the node network (e.g. 10.0.0.0/24)."
  type        = string
  default     = "10.0.0.0/24"
}

variable "network_gateway" {
  description = "Default gateway for all nodes."
  type        = string
  default     = "10.0.0.1"
}

variable "domain_name_server" {
  description = "DNS server address for all nodes. Using 1.1.1.1 to avoid issues with Proxmox SDN not providing DNS forwarding."
  type        = string
  default     = "1.1.1.1"
}

variable "vlan_tag" {
  description = "VLAN tag for node network interfaces. Set to 0 to disable VLAN tagging."
  type        = number
  default     = 0
}

# =============================================================================
# Storage
# =============================================================================

variable "longhorn_disk_size" {
  description = "Size in GB of the dedicated Longhorn data disk attached to each worker node."
  type        = number
  default     = 200
}

variable "longhorn_disk_device" {
  description = <<-EOT
    Block device path for the dedicated Longhorn disk on worker nodes.
    Use /dev/sdb for SCSI (default Proxmox SCSI controller), /dev/vdb for VirtIO, /dev/nvme1n1 for NVMe.
  EOT
  type        = string
  default     = "/dev/sdb"
}

# =============================================================================
# Networking — Cilium
# =============================================================================

variable "cilium_version" {
  description = "Cilium Helm chart version. Used both for rendering the CNI manifest injected into Talos and for the Helm release. See: https://github.com/cilium/cilium/releases"
  type        = string
  default     = "1.19.3"
}


