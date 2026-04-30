resource "proxmox_virtual_environment_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = var.proxmox_storage_device
  node_name    = var.proxmox_target_node
  url          = var.talos_linux_iso_image_url
  file_name    = var.talos_linux_iso_image_filename
}

resource "proxmox_virtual_environment_vm" "kubernetes_control_plane" {
  depends_on = [proxmox_virtual_environment_download_file.talos_iso]
  for_each   = var.node_data.controlplanes

  name        = format("%s-cp-%s", var.cluster_name, index(keys(var.node_data.controlplanes), each.key))
  description = "Talos Kubernetes Control Plane"
  node_name   = var.proxmox_target_node

  machine = "q35"
  bios    = "ovmf"
  boot_order = ["scsi0", "ide2"]

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

  agent {
    enabled = true
  }

  vga {
    type = "std"
  }

  cdrom {
    enabled   = true
    file_id   = proxmox_virtual_environment_download_file.talos_iso.id
    interface = "ide2"
  }

  disk {
    datastore_id = var.proxmox_storage_device
    interface    = "scsi0"
    size         = 50
    file_format  = "raw"
    discard      = "on"
  }

  efi_disk {
    datastore_id = var.proxmox_storage_device
    file_format  = "raw"
    type         = "4m"
  }

  network_device {
    bridge      = var.proxmox_network_bridge
    vlan_id     = var.vlan_tag == 0 ? null : var.vlan_tag
    mac_address = "02:00:00:00:00:${format("%02X", split(".", each.key)[3])}"
  }

  initialization {
    datastore_id = var.proxmox_storage_device
    interface    = "ide0"
    type         = "nocloud"
    ip_config {
      ipv4 {
        address = "${each.key}/24"
        gateway = var.network_gateway
      }
    }
  }

  operating_system {
    type = "l26"
  }
}

resource "proxmox_virtual_environment_vm" "kubernetes_worker" {
  depends_on = [proxmox_virtual_environment_download_file.talos_iso]
  for_each   = var.node_data.workers

  name        = format("%s-worker-%s", var.cluster_name, index(keys(var.node_data.workers), each.key))
  description = "Talos Kubernetes Worker Node"
  node_name   = var.proxmox_target_node

  machine = "q35"
  bios    = "ovmf"
  boot_order = ["scsi0", "ide2"]

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 16384
  }

  agent {
    enabled = true
  }

  vga {
    type = "std"
  }

  cdrom {
    enabled   = true
    file_id   = proxmox_virtual_environment_download_file.talos_iso.id
    interface = "ide2"
  }

  disk {
    datastore_id = var.proxmox_storage_device
    interface    = "scsi0"
    size         = 50
    file_format  = "raw"
    discard      = "on"
  }

  disk {
    datastore_id = var.proxmox_storage_device
    interface    = "scsi1"
    size         = var.longhorn_disk_size
    file_format  = "raw"
    discard      = "on"
  }

  efi_disk {
    datastore_id = var.proxmox_storage_device
    file_format  = "raw"
    type         = "4m"
  }

  network_device {
    bridge      = var.proxmox_network_bridge
    vlan_id     = var.vlan_tag == 0 ? null : var.vlan_tag
    mac_address = "02:00:00:00:00:${format("%02X", split(".", each.key)[3])}"
  }

  initialization {
    datastore_id = var.proxmox_storage_device
    interface    = "ide0"
    type         = "nocloud"
    ip_config {
      ipv4 {
        address = "${each.key}/24"
        gateway = var.network_gateway
      }
    }
  }

  operating_system {
    type = "l26"
  }
}
