# The three Talos nodes (docs/architecture.md, "Nodes").
# Credentials come from infra/op.env through `op run` (mise tasks infra:*);
# this file holds no secret and no account-specific value.

terraform {
  required_version = "~> 1.13"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.122.0"
    }
  }

  # D24. Endpoint, region and keys come from AWS_ENDPOINT_URL_S3, AWS_REGION,
  # AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY.
  backend "s3" {
    bucket                      = "homelab"
    key                         = "tofu/homelab.tfstate"
    use_path_style              = true
    use_lockfile                = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }

  encryption {
    key_provider "pbkdf2" "state" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }
    state {
      method   = method.aes_gcm.state
      enforced = true
    }
    plan {
      method   = method.aes_gcm.state
      enforced = true
    }
  }
}

variable "state_passphrase" {
  type      = string
  sensitive = true
}

variable "proxmox_token_id" {
  type = string
}

variable "proxmox_token_secret" {
  type      = string
  sensitive = true
}

provider "proxmox" {
  endpoint  = "https://10.0.0.1:8006/"
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  insecure  = true # the host uses its self-signed certificate
}

locals {
  nodes = {
    k8s-1 = { vm_id = 201, address = "10.0.6.11" }
    k8s-2 = { vm_id = 202, address = "10.0.6.12" }
    k8s-3 = { vm_id = 203, address = "10.0.6.13" }
  }
}

resource "proxmox_virtual_environment_vm" "node" {
  for_each = local.nodes

  vm_id     = each.value.vm_id
  name      = each.key
  node_name = "pve"
  pool_id   = "homelab"

  machine         = "q35"
  bios            = "ovmf"
  scsi_hardware   = "virtio-scsi-pci"
  on_boot         = true
  stop_on_destroy = true

  operating_system {
    type = "l26"
  }

  cpu {
    type  = "host"
    cores = 2
  }

  memory {
    dedicated = 8192
    floating  = 0 # no ballooning
  }

  agent {
    enabled = true
    timeout = "3m"
  }

  efi_disk {
    datastore_id      = "local-zfs"
    type              = "4m"
    pre_enrolled_keys = false
  }

  disk {
    interface    = "scsi0"
    datastore_id = "local-zfs"
    import_from  = "local:import/talos-v1.14.6-nocloud-amd64.qcow2"
    size         = 20
    discard      = "on"
    ssd          = true
  }

  disk {
    interface    = "scsi1"
    datastore_id = "local-zfs"
    size         = 100
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge = "k8s"
    model  = "virtio"
  }

  initialization {
    datastore_id = "local-zfs"
    interface    = "ide2"
    ip_config {
      ipv4 {
        address = "${each.value.address}/24"
        gateway = "10.0.6.1"
      }
    }
    dns {
      servers = ["1.1.1.1", "9.9.9.9"]
    }
  }
}
