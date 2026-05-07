terraform {
  backend "s3" {
    bucket = "general"
    key    = "homelab-terraform-state/homeops.tfstate"
    region = "us-ashburn-1" # Update to your OCI region (e.g., eu-frankfurt-1)
    # REQUIRED: Uncomment and set your OCI Object Storage S3-compatible endpoint URL.
    # Without this, Terraform will attempt to connect to AWS S3 and fail.
    # Format: https://<namespace>.compat.objectstorage.<region>.oraclecloud.com
    # endpoint = "https://<namespace>.compat.objectstorage.us-ashburn-1.oraclecloud.com"

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
      version = "~> 0.106.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.11.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.8.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true
}

# helm.local: used only for rendering Helm chart manifests locally (helm_template data source) for Cilium inline inject.
provider "helm" {
  alias = "local"
}
