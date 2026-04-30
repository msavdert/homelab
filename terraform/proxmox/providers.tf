terraform {
  backend "s3" {
    bucket                      = "general"
    key                         = "homelab-terraform-state/terraform.tfstate"
    region                      = "us-ashburn-1" # Update to your OCI region (e.g., eu-frankfurt-1)
#    endpoint                    = "PLACEHOLDER_URL" # Paste your OCI S3 endpoint URL here

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
      version = "~> 0.60.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.10.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true
}
