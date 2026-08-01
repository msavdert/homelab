variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint, e.g. https://pve:8006/ (over Tailscale)."
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token in `user@realm!tokenid=secret` format, for the least-privilege `terraform@pve` user (see README)."
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = <<-EOT
    Skip TLS certificate verification against the Proxmox API. The `pve`
    node currently serves its default self-signed PVE cluster CA
    certificate (not a publicly trusted CA, and not imported into the
    operator's local trust store), so this defaults to true. Set to false
    once the Proxmox API is served with a certificate this machine trusts.
  EOT
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Proxmox node name to provision on."
  type        = string
  default     = "pve"
}

variable "image_storage" {
  description = "Proxmox storage (content type `import`) to download the cloud image into."
  type        = string
  default     = "local"
}

variable "disk_storage" {
  description = "Proxmox storage (content type `images`/`rootdir`) for VM/template disks."
  type        = string
  default     = "local-zfs"
}

variable "network_bridge" {
  description = "Proxmox network bridge for VM network devices."
  type        = string
  default     = "vmbr0"
}

variable "debian_image_url" {
  description = "URL of the Debian 12 (bookworm) generic cloud qcow2 image (see ADR-0002)."
  type        = string
  default     = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
}

variable "debian_image_file_name" {
  description = "File name to store the downloaded cloud image under in Proxmox storage."
  type        = string
  default     = "debian-12-generic-amd64.qcow2"
}

variable "template_vm_id" {
  description = "VM ID for the Debian 12 cloud-init template."
  type        = number
  default     = 9000
}

variable "template_name" {
  description = "Name of the Debian 12 cloud-init template."
  type        = string
  default     = "debian-12-cloudinit-template"
}

variable "template_disk_size" {
  description = "Disk size, in GB, of the template's boot disk. Must be >= the source image's virtual size; grown per-clone as needed."
  type        = number
  default     = 8
}
