# GitHub CI/CD Best Practices for Terraform

This guide outlines how to implement a production-ready, GitOps-driven CI/CD pipeline for your homelab using **GitHub Actions**.

## 1. The GitOps Workflow
In a professional setup, we avoid running `terraform apply` from a local terminal. Instead, we follow this flow:
1. **Feature Branch:** Create a branch for your changes.
2. **Pull Request (PR):** Open a PR to the `main` branch.
3. **Automated Plan:** GitHub Actions runs `terraform plan` and posts the output as a comment on the PR.
4. **Review:** Peer review (or self-review) the plan output.
5. **Merge:** Merge the PR into `main`.
6. **Automated Apply:** GitHub Actions runs `terraform apply` only after the merge.

---

## 2. Pipeline Architecture

### Triggers
- **On Pull Request:** Triggers `fmt`, `validate`, and `plan`.
- **On Push to Main:** Triggers `apply`.

### Concurrency & Locking
Since S3-compatible backends (R2/OCI) do not support native DynamoDB locking, we use GitHub's `concurrency` feature to ensure only one job runs at a time:
```yaml
concurrency:
  group: terraform-production
  cancel-in-progress: false
```

---

## 3. Security: GitHub Secrets
Store your sensitive API keys in your GitHub Repository under **Settings > Secrets and variables > Actions**:

| Secret Name | Description |
| :--- | :--- |
| `AWS_ACCESS_KEY_ID` | Your R2 or OCI Access Key. |
| `AWS_SECRET_ACCESS_KEY` | Your R2 or OCI Secret Key. |
| `PROXMOX_API_TOKEN_ID` | Proxmox API Token ID. |
| `PROXMOX_API_TOKEN_SECRET` | Proxmox API Token Secret. |

---

## 4. Recommended Workflow Structure

Create a file at `.github/workflows/terraform.yml`:

```yaml
name: "Terraform CI/CD"

on:
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]

permissions:
  contents: read
  pull-requests: write # Required for posting PR comments

jobs:
  terraform:
    runs-on: ubuntu-latest
    concurrency: production # Simple lock mechanism
    
    env:
      AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
      AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      # Add other Proxmox/Talos secrets here

    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        run: terraform init

      - name: Terraform Format Check
        run: terraform fmt -check

      - name: Terraform Validate
        run: terraform validate

      - name: Terraform Plan
        if: github.event_name == 'pull_request'
        run: terraform plan -no-color
        continue-on-error: true

      - name: Terraform Apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply -auto-approve
```

---

## 5. Advanced Best Practices

### Automated PR Comments
Use a specialized action like `actions-terraform-config` or a simple script to post the `terraform plan` output directly to your Pull Request. This allows you to review infrastructure changes without leaving the GitHub UI.

### Static Analysis (Security Scanning)
Add a step to run **Checkov** or **tfsec** before the plan:
```yaml
      - name: Run Checkov
        uses: bridgecrewio/checkov-action@master
        with:
          directory: terraform/proxmox
```

### Environment Isolation
Use **GitHub Environments** (e.g., `production`) to store secrets and require **Manual Approval** before an `apply` is executed on the `main` branch. This adds a "Human-in-the-loop" safety gate.

---

## 6. Summary: Why this is the "Best" Way
1. **Consistency:** The environment is always the same (Ubuntu runner).
2. **Auditability:** Every change is linked to a PR and a specific user.
3. **Safety:** Concurrency groups prevent state corruption in R2/OCI.
4. **Automation:** No more "did I forget to run apply?" questions.
