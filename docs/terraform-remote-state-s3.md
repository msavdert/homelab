# Terraform Remote State with S3-Compatible Backends

This guide provides detailed instructions on how to configure and manage Terraform remote state using S3-compatible storage providers such as **Cloudflare R2** or **OCI (Oracle Cloud Infrastructure) Object Storage**.

## 1. Overview
By default, Terraform stores state locally in a `terraform.tfstate` file. In a team environment or for better reliability, it is best practice to use **Remote State**. This ensures:
- **Shared State:** Team members can work on the same infrastructure.
- **Security:** State files often contain sensitive data; remote backends can be secured with IAM.
- **Durability:** Remote storage prevents accidental loss of the state file.

---

## 2. Prerequisites

### For Cloudflare R2
1. **Create a Bucket:** Create a bucket in the Cloudflare R2 dashboard (e.g., `homelab-tfstate`).
2. **Generate API Tokens:**
   - Go to R2 -> Manage R2 API Tokens.
   - Create a token with **Object Read & Write** permissions for your specific bucket.
   - Save the `Access Key ID` and `Secret Access Key`.
3. **Account ID:** Note your Cloudflare Account ID (found in the dashboard URL or account settings).

### For OCI Object Storage
1. **Create a Bucket:** Create a bucket in your OCI Tenancy (e.g., `homelab-tfstate`).
2. **Customer Secret Keys:**
   - Go to User Settings -> Resources -> Customer Secret Keys.
   - Generate a new secret key.
   - Save the `Access Key ID` and `Secret Access Key`.
3. **Namespace:** Note your OCI Namespace (found in Tenancy Details).

---

## 3. Configuration

### S3 Backend Block Template
Since R2 and OCI are not AWS, we must use the `s3` backend with custom `endpoint` and `skip_*` flags to disable AWS-specific metadata checks.

#### **Option A: Cloudflare R2 Configuration**
```hcl
terraform {
  backend "s3" {
    bucket                      = "homelab-tfstate"
    key                         = "proxmox/terraform.tfstate"
    region                      = "us-east-1" # Arbitrary for R2 but required
    endpoint                    = "https://<YOUR_ACCOUNT_ID>.r2.cloudflarestorage.com"
    
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}
```

#### **Option B: OCI Object Storage Configuration**
```hcl
terraform {
  backend "s3" {
    bucket                      = "homelab-tfstate"
    key                         = "proxmox/terraform.tfstate"
    region                      = "us-ashburn-1" # Your OCI region
    endpoint                    = "https://<NAMESPACE>.compat.objectstorage.<REGION>.oraclecloud.com"
    
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

## 4. Security Best Practices

**IMPORTANT:** Never hardcode your Access Keys in the `.tf` files.

### Use Environment Variables
Terraform automatically picks up credentials from standard AWS environment variables:
```bash
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
```

### Use a Backend Config File
You can keep the configuration separate and provide it during initialization:
1. Create `backend.conf`:
   ```hcl
   bucket   = "homelab-tfstate"
   endpoint = "https://..."
   # ... other settings
   ```
2. Initialize with:
   ```bash
   terraform init -backend-config=backend.conf
   ```

---

## 5. Migration Guide (Moving from Local to Remote)

If you already have a `terraform.tfstate` file locally, follow these steps to migrate it safely:

1. **Backup:** Copy your `terraform.tfstate` to a safe place.
2. **Add Backend Block:** Add the `terraform { backend "s3" { ... } }` block to your code (e.g., in `providers.tf`).
3. **Initialize Migration:**
   ```bash
   terraform init
   ```
4. **Confirm Migration:** Terraform will detect the existing local state and ask:
   > Do you want to copy existing state to the new backend?
   - Type **`yes`**.
5. **Verify:** Check your R2/OCI bucket to ensure the `.tfstate` file has been uploaded.
6. **Cleanup:** Once verified, you can delete the local `terraform.tfstate` and `.terraform.tfstate.lock.info` files.

---

## 6. Initialization from Scratch

For a brand-new project:
1. Define the `backend "s3"` block.
2. Ensure the bucket exists in your provider.
3. Run `terraform init`.
4. Terraform will initialize an empty state in the remote bucket.

---

## 7. State Locking Considerations
Standard S3 backends use **AWS DynamoDB** for state locking.
- **Cloudflare R2** and **OCI** do **not** natively support DynamoDB locking through the S3 API.
- In a team environment, be careful: if two people run `terraform apply` at the same time, the state could be corrupted.
- **Recommendation:** Use a CI/CD pipeline (like GitHub Actions) to run Terraform, which ensures only one job runs at a time.
