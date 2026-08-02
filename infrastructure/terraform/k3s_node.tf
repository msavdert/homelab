# Phase 1's k3s cluster VM: a single-node clone of the Phase 0 template
# (ADR-0005), attached to the private k3snet SDN network (ADR-0008). k3s
# itself, Cilium, and ArgoCD are day-0 manual bootstrap steps per
# ADR-0006/ADR-0007 — this resource only provisions the VM they install
# onto, not the cluster software.
resource "proxmox_virtual_environment_vm" "k3s_node" {
  name      = "k3s-node-01"
  node_name = var.proxmox_node
  vm_id     = var.k3s_node_vm_id

  agent {
    enabled = true
    type    = "virtio"
  }

  clone {
    vm_id = proxmox_virtual_environment_vm.debian_12_template.vm_id
    full  = true
  }

  cpu {
    cores = var.k3s_node_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.k3s_node_memory
  }

  disk {
    datastore_id = var.disk_storage
    interface    = "scsi0"
    size         = var.k3s_node_disk_size
  }

  scsi_hardware = "virtio-scsi-pci"

  # Serial console, for boot-time debugging when SSH/cloud-init hasn't come
  # up yet (`qm terminal <vmid>` on the host).
  serial_device {}

  vga {
    type = "serial0"
  }

  network_device {
    bridge = "k3snet"
    model  = "virtio"
  }

  initialization {
    datastore_id = var.disk_storage
    interface    = "ide2"

    # `local:snippets/k3s-node-cloud-init.yaml` is placed manually on the
    # host (see infrastructure/terraform/README.md) rather than through
    # `proxmox_virtual_environment_file` — that resource uploads snippets
    # over a raw SSH connection to the node's public IP, which this
    # environment has no working key/agent auth for (separate from the
    # Tailscale-mediated `ssh root@pve` access used elsewhere in this repo).
    #
    # Proxmox's `--cicustom user=...` (what `user_data_file_id` sets)
    # REPLACES cloud-init's user-data wholesale — it does NOT merge with
    # `user_account`/`keys` below. The admin user, sudo grant, and SSH key
    # (matching var.k3s_ssh_public_key) are therefore defined inside that
    # snippet file, not in this `initialization` block. `user_account` is
    # deliberately omitted here rather than left in as dead, ignored config.
    user_data_file_id = "local:snippets/k3s-node-cloud-init.yaml"

    ip_config {
      ipv4 {
        address = "${var.k3s_node_ip}/24"
        gateway = "10.0.1.1"
      }
    }
  }

  operating_system {
    type = "l26"
  }

  # `clone` isn't stored server-side, so a freshly imported resource shows
  # it as a spurious forces-replacement diff on the next plan (same cause
  # as `url`/`import_from` in image.tf/template.tf).
  lifecycle {
    ignore_changes = [clone]
  }
}
