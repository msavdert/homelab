# Terraform Remote State with OCI Object Storage

This project uses **OCI (Oracle Cloud Infrastructure) Object Storage** as a remote backend for Terraform state. This allows for portable infrastructure management and consistent state across different environments.

## 1. Remote State Architecture

All state files are stored in a single bucket named `general`, separated by prefixes (folders) to avoid collisions:

| Layer | Key Path |
| :--- | :--- |
| **Proxmox/Infrastructure** | `homelab-terraform-state/terraform.tfstate` |
| **Kubernetes/Apps** | `homelab-terraform-state/kubernetes.tfstate` |

---

## 2. Required Environment Variables

To interact with the remote state, you must set these variables in your shell. It is recommended to use a secret manager or `.env` file (never commit these to Git).

```bash
# OCI Customer Secret Keys
export AWS_ACCESS_KEY_ID="your_access_key"
export AWS_SECRET_ACCESS_KEY="your_secret_key"

# OCI S3 Compatibility Fixes (Mandatory)
# Fixes: "501 NotImplemented: AWS chunked encoding not supported"
export AWS_REQUEST_CHECKSUM_CALCULATION=WHEN_REQUIRED

# Optional: Set endpoint via env var to keep providers.tf generic
export AWS_ENDPOINT_URL_S3="https://<NAMESPACE>.compat.objectstorage.<REGION>.oraclecloud.com"
```

---

## 3. Provider Configuration Template

Each `providers.tf` file should contain the following backend block:

```hcl
terraform {
  backend "s3" {
    bucket                      = "general"
    key                         = "homelab-terraform-state/<PROJECT_NAME>.tfstate"
    region                      = "us-ashburn-1" # Update to your OCI region
    # endpoint is picked up from AWS_ENDPOINT_URL_S3 env var
    
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}
```

---

## 4. Migration Guide

To move a local state to the remote backend:

1. Add the `backend "s3"` block to `providers.tf`.
2. Set the environment variables in Section 2.
3. Run `terraform init`.
4. When prompted to copy existing state, type **`yes`**.
5. Once verified, delete the local `terraform.tfstate` and `.terraform.tfstate.lock.info` files.

---

## 5. Locking Considerations
OCI S3 compatibility does not natively support state locking.
- **Precaution:** Avoid running `terraform apply` from two different sources simultaneously.
- **Best Practice:** Use a CI/CD pipeline (e.g., GitHub Actions) to centralize runs and prevent concurrency issues.
