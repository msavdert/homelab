# Renovate Dependency Management Guide

This document outlines the setup, integration, and best practices for using [Renovate](https://docs.renovatebot.com/) within this homelab repository.

## Overview

Renovate is an automated dependency update tool that monitors your repository for outdated dependencies and automatically creates Pull Requests (PRs) to update them. In this project, it manages:

- **Argo CD Applications**: Monitors `apps/` for Helm chart versions (`targetRevision`).
- **Terraform**: Monitors `terraform/` for Provider and Module versions.

---

## Installation: GitHub App (Recommended)

The easiest way to integrate Renovate is by using the official **Mend Renovate** GitHub App.

### Step-by-Step Setup
1.  Go to the [Renovate GitHub App page](https://github.com/apps/renovate).
2.  Click **Install**.
3.  Select your GitHub account or organization.
4.  Choose **Only select repositories** and select this repository (`homelab`).
5.  Click **Install & Authorize**.
6.  **Mend Onboarding Screens**:
    *   **Select Product**: Choose **Renovate Only**.
    *   **Select Mode**: Choose **Scan and Alert**. This ensures Renovate creates Pull Requests rather than just scanning silently.

---

## Working Configuration (`renovate.json`)

Our project uses a specific configuration to ensure Argo CD manifests are correctly detected. Unlike Terraform, the Argo CD manager requires an explicit `fileMatch` pattern.

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    ":rebaseStalePrs"
  ],
  "argocd": {
    "fileMatch": [
      "(^|/)apps/.+\\.yaml$"
    ]
  },
  "packageRules": [
    {
      "matchManagers": ["terraform"],
      "groupName": "Terraform Updates"
    },
    {
      "matchManagers": ["argocd"],
      "groupName": "ArgoCD Updates"
    }
  ]
}
```

### Key Components:
- **`config:recommended`**: Enables standard best practices for dependency scanning.
- **`argocd.fileMatch`**: Tells Renovate to scan all `.yaml` files inside the `apps/` directory (and subdirectories) for Argo CD `Application` manifests.
- **`packageRules`**: Groups multiple updates into single PRs (e.g., all Terraform providers together) to reduce PR noise.

---

## Using the Dependency Dashboard

Renovate creates a persistent Issue titled **"Dependency Dashboard"** in your repository. This is your control panel for managing updates.

### 1. Config Migration
If you see a checkbox for **"Config Migration Needed"**, select it. Renovate will open a PR to update your `renovate.json` to the latest standards. This is a safe and recommended operation.

### 2. Rate-Limiting & Major Updates
Renovate often rate-limits **Major** updates (e.g., v2.0.0 to v3.0.0) to prevent breaking your infrastructure all at once.
- **Major Updates**: Usually contain breaking changes. Review the linked Release Notes carefully.
- **Minor/Patch Updates**: Generally safe and grouped in the PRs you see immediately.

### 3. Manual Triggers
- **Rebase/Retry**: You can check boxes in the dashboard to force Renovate to recreate or update a specific PR.
- **Run Again**: At the bottom of the dashboard, there is a checkbox to trigger a fresh scan of the entire repository. Use this after merging PRs to speed up the detection of the next set of updates.

---

## Post-Installation Workflow

Once Renovate is active, follow this routine to keep your homelab healthy:

### 1. Review the Pull Requests
When a PR arrives:
- **Read the Release Notes**: Renovate automatically embeds changelogs in the PR description. Check for any "Breaking Changes".
- **Verify Terraform**: For Terraform PRs, it is recommended to run `terraform plan` locally to ensure no unexpected infrastructure changes occur.

### 2. Merge and Observe
- **Merge**: Once satisfied, merge the PR into `main`.
- **Observe Argo CD**: Watch your Argo CD dashboard. It will detect the Git change and synchronize the new versions (e.g., updating Longhorn or Cilium) into your cluster.

### 3. Future Automation (Optional)
As you gain confidence in your setup, you can enable **Automerge** for specific types of updates (like `patch` versions) by adding the following to your `renovate.json`:
```json
{
  "packageRules": [
    {
      "matchUpdateTypes": ["patch"],
      "automerge": true
    }
  ]
}
```
*Note: Only enable automerge if you have automated tests to verify the changes.*

---

## Troubleshooting

### The "Action Required: Fix Renovate Configuration" Issue
If you see this error, it usually means there is a syntax error or an invalid manager configuration.
- **Solution**: Ensure your `fileMatch` regex is correct. Using `(^|/)` at the start of the pattern helps Renovate match directories correctly regardless of the root path.
- **Validation**: You can validate your config locally using:
  ```bash
  npx --yes --package renovate -- renovate-config-validator
  ```

---

## Useful Resources
- [Renovate Official Documentation](https://docs.renovatebot.com/)
- [Argo CD Manager Configuration](https://docs.renovatebot.com/modules/manager/argocd/)
- [Terraform Manager Configuration](https://docs.renovatebot.com/modules/manager/terraform/)
