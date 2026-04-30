variable "proxmox_endpoint" {
  description = "Proxmox API endpoint (e.g. https://proxmox:8006/)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API Token (e.g. root@pam!token=uuid)"
  type        = string
  sensitive   = true
}

variable "proxmox_target_node" {
  description = "Proxmox target node name"
  type        = string
}

variable "proxmox_storage_device" {
  description = "Proxmox storage device name"
  type        = string
}

variable "proxmox_network_bridge" {
  description = "The network bridge to use for the VMs (e.g., vmbr0, vnet1)"
  type        = string
  default     = "vnet1"
}

variable "longhorn_disk_size" {
  description = "Size of the dedicated disk for Longhorn storage on worker nodes (in GB)"
  type        = number
  default     = 100
}

variable "talos_version" {
  type    = string
  default = "1.13.0"
}

variable "kubernetes_version" {
  type    = string
  default = "1.36.0"
}

variable "talos_linux_iso_image_url" {
  description = "URL of the Talos ISO image for initially booting the VM"
  type        = string
  default     = "https://factory.talos.dev/image/a7bcadbc1b6d03c0e687be3a5d9789ef7113362a6a1a038653dfd16283a92b6b/v1.13.0/nocloud-amd64.iso"
}

variable "talos_linux_iso_image_filename" {
  description = "Filename of the Talos ISO image for initially booting the VM"
  type        = string
  default     = "talos-linux-v1.13.0-nocloud-amd64.iso"
}

variable "cluster_name" {
  description = "A name to provide for the Talos cluster"
  type        = string
  default     = "talos"
}

variable "cluster_vip_shared_ip" {
  description = "Shared virtual IP address for control plane nodes"
  type        = string
  default     = "10.0.0.2"
}

variable "node_data" {
  description = "A map of node data"
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
        install_image = "factory.talos.dev/nocloud-installer/a7bcadbc1b6d03c0e687be3a5d9789ef7113362a6a1a038653dfd16283a92b6b:v1.13.0"
      },
    }
    workers = {
      "10.0.0.11" = {
        install_disk  = "/dev/sda"
        install_image = "factory.talos.dev/nocloud-installer/a7bcadbc1b6d03c0e687be3a5d9789ef7113362a6a1a038653dfd16283a92b6b:v1.13.0"
      },
      "10.0.0.12" = {
        install_disk  = "/dev/sda"
        install_image = "factory.talos.dev/nocloud-installer/a7bcadbc1b6d03c0e687be3a5d9789ef7113362a6a1a038653dfd16283a92b6b:v1.13.0"
      },
      "10.0.0.13" = {
        install_disk  = "/dev/sda"
        install_image = "factory.talos.dev/nocloud-installer/a7bcadbc1b6d03c0e687be3a5d9789ef7113362a6a1a038653dfd16283a92b6b:v1.13.0"
      },
    }
  }
}

variable "network" {
  description = "Network for all nodes"
  type        = string
  default     = "10.0.0.0/24"
}

variable "network_gateway" {
  description = "Network gateway for all nodes"
  type        = string
  default     = "10.0.0.1"
}

variable "domain_name_server" {
  description = "DNS for all nodes"
  type        = string
  default     = "10.0.0.1"
}

variable "vlan_tag" {
  description = "Vlan tag for all nodes, default does not configure a Vlan"
  type        = number
  default     = 0
}
