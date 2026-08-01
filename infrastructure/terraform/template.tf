# The Debian 12 cloud-init VM template. Every workload VM is a Terraform
# clone of this template (not built yet — see ADR-0002); this resource only
# creates the template itself.
resource "proxmox_virtual_environment_vm" "debian_12_template" {
  name      = var.template_name
  node_name = var.proxmox_node
  vm_id     = var.template_vm_id
  template  = true

  # Templates should never be started directly; clones are.
  started = false

  agent {
    enabled = true
    type    = "virtio"
  }

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = var.disk_storage
    interface    = "scsi0"
    import_from  = local.debian_image_volume_id
    size         = var.template_disk_size
    file_format  = "raw"
  }

  scsi_hardware = "virtio-scsi-pci"

  # Cloud-init drive. Left with no per-instance user-data at the template
  # level; clones supply their own hostname/SSH keys/networking.
  initialization {
    datastore_id = var.disk_storage
    interface    = "ide2"
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }
}
