terraform {
  backend "s3" {
    bucket                      = "general"
    key                         = "homelab-terraform-state/kubernetes.tfstate"
    region                      = "us-ashburn-1" # Same region as Proxmox layer
    # endpoint                    = "OCI_URL_HERE"

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15.0"
    }
  }
}

provider "kubernetes" {
  config_path    = var.kubernetes_config_path
  config_context = var.Kubernetes_config_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kubernetes_config_path
    config_context = var.Kubernetes_config_context
  }
}
