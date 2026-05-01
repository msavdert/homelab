# Renovate Dependency Management Guide

This document outlines the setup, integration, and best practices for using [Renovate](https://docs.renovatebot.com/) within this homelab repository.

## Overview

Renovate is an automated dependency update tool that monitors your repository for outdated dependencies and automatically creates Pull Requests (PRs) to update them. In this project, it is primarily used for:

- **Argo CD Applications**: Updating `targetRevision` for Helm charts.
- **Terraform**: Updating Provider and Module versions.
- **Container Images**: Updating tags in Kubernetes manifests.

---

## Installation: GitHub App (Recommended)

The easiest way to integrate Renovate with GitHub is by using the official **Mend Renovate** GitHub App.

### Step-by-Step Setup
1.  Go to the [Renovate GitHub App page](https://github.com/apps/renovate).
2.  Click **Install**.
3.  Select your GitHub account or organization.
4.  Choose **Only select repositories** and select this repository (`homelab`).
5.  Click **Install & Authorize**.
6.  **Mend Onboarding Screens**:
    *   **Select Product**: Choose **Renovate Only**. (The "Mend Application Security" option requires a paid license).
    *   **Select Mode**: Choose **Scan and Alert**. This ensures Renovate creates Pull Requests and Issues rather than just scanning silently.

---

## The Onboarding Process

Once the app is installed, Renovate will not immediately start opening PRs for every dependency. Instead:

1.  **Configure Renovate PR**: Renovate will open a single PR titled "Configure Renovate".
2.  **Review the PR**: This PR contains a default `renovate.json` file. It will also provide a summary of all dependencies it found in your repo.
3.  **Merge the PR**: Once you merge this onboarding PR, Renovate becomes active and will start managing your dependencies based on the configuration.

---

## Implementation Strategy & Best Practices

To avoid being overwhelmed by PRs ("PR fatigue") and to ensure stability, follow these best practices:

### 1. Noise Reduction

#### Dependency Grouping
Group related updates together to reduce the number of open PRs. For example, grouping all Terraform providers into a single PR.
```json
{
  "packageRules": [
    {
      "matchManagers": ["terraform"],
      "groupName": "Terraform Providers"
    }
  ]
}
```

#### Scheduling
Limit when Renovate creates PRs. This prevents a flood of notifications during your workday.
```json
{
  "schedule": ["before 8am on monday"]
}
```

### 2. Dependency Dashboard
Renovate creates a "Dependency Dashboard" issue in your repository. Use this to:
- See a summary of all pending updates.
- Manually trigger a PR for a specific update.
- Re-trigger failed PRs.

### 3. Automerging
For low-risk updates (e.g., `patch` versions or specific non-breaking providers), you can enable automerge if your CI/CD pipeline passes.
> [!IMPORTANT]
> Only enable automerge if you have robust automated testing (e.g., `terraform plan` checks or Kubernetes linting).

### 4. GitOps Specifics (Argo CD & Terraform)
Renovate is highly compatible with GitOps:
- **Argo CD**: It detects `targetRevision` in `Application` manifests and updates them.
- **Terraform**: It parses `.tf` files and `.terraform.lock.hcl` to ensure providers are kept up to date.

---

## Recommended Configuration (`renovate.json`)

Here is a recommended starting configuration for this repository:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    ":rebaseStalePrs",
    ":enableHelpfulLabels",
    ":prHourlyLimitNone",
    ":prConcurrentLimit20"
  ],
  "argocd": {
    "fileMatch": ["apps/.+\\.yaml$"]
  },
  "terraform": {
    "fileMatch": ["terraform/.+\\.tf$"]
  },
  "packageRules": [
    {
      "matchUpdateTypes": ["minor", "patch"],
      "matchManagers": ["terraform"],
      "groupName": "Terraform Dependencies"
    },
    {
      "matchUpdateTypes": ["minor", "patch"],
      "matchManagers": ["argocd"],
      "groupName": "ArgoCD App Updates"
    }
  ]
}
```

## Useful Resources
- [Renovate Official Documentation](https://docs.renovatebot.com/)
- [Renovate Configuration Options](https://docs.renovatebot.com/configuration-options/)
- [Renovate Templates](https://docs.renovatebot.com/presets-config/)
