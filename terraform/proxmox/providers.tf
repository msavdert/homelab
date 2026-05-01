terraform {
  backend "s3" {
    bucket                      = "general"
    key                         = "homelab-terraform-state/proxmox.tfstate"
    region                      = "us-ashburn-1" # Update to your OCI region (e.g., eu-frankfurt-1)
#    endpoint                    = "OCI_URL_HERE" # Paste your OCI S3 endpoint URL here

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.104.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.11.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true
}
