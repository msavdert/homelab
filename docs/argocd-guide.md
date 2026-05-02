# ArgoCD Best Practices & Project Usage Guide

This document outlines how ArgoCD is utilized within this homelab repository and the established patterns for managing Kubernetes applications.

## 📁 Repository Structure

We follow a modular approach to separate base configurations from production deployments:

- **`apps/base/<app-name>/`**: Contains the "source of truth" for an application's configuration. This typically includes a `values.yaml` for Helm-based apps or raw YAML manifests.
- **`apps/production/<app-name>.yaml`**: Contains the ArgoCD `Application` manifest. This is the entry point that connects the cluster to the repository.

## 🏗 Key Patterns

### 1. Multi-Source Applications
For modern deployments, we use ArgoCD's **Multiple Sources** feature. This allows us to use an upstream Helm chart while referencing a local `values.yaml` file within the same Application definition.

**Example Pattern:**
```yaml
spec:
  sources:
    - repoURL: https://charts.example.com
      chart: my-chart
      helm:
        valueFiles:
          - $values/apps/base/my-app/values.yaml
    - repoURL: https://github.com/msavdert/homelab.git
      ref: values
```

### 2. Sync Waves
We use sync waves to control the order of deployment. Core infrastructure (storage, CRDs) should have lower values (deploy first) than applications.
- `-10`: Infrastructure (Longhorn, Gateway API CRDs)
- `-8`: System Utilities (Cert-manager)
- `-4`: Monitoring/Logging Base
- `0`: General Applications

### 3. Including & Excluding Files
Sometimes a directory contains files that should not be managed by ArgoCD (e.g., documentation, scripts). We use the `directory` field to control this.

- **`exclude`**: Prevents specific files or patterns from being synced.
- **`include`**: Forces only specific files or patterns to be synced.

**Example (Excluding READMEs):**
```yaml
source:
  path: apps/base/my-app
  directory:
    exclude: "README.md"
```

**Common Patterns:**
- `exclude: "*.txt"`: Ignore all text files.
- `exclude: "{test-*,README.md}"`: Ignore multiple patterns using glob syntax.

## 🛡 Best Practices

- **Automated Pruning**: Always enable `prune: true` in the `syncPolicy` to ensure that resources deleted from Git are also deleted from the cluster.
- **Server-Side Apply**: Use `ServerSideApply=true` to handle large manifests (like CRDs) and avoid field manager conflicts.
- **Avoid Plain YAML for Secrets**: Use the 1Password operator (`OnePasswordItem`) or Sealed Secrets instead of committing raw Secret manifests.
- **Documentation**: Always include a `README.md` in the `apps/base/<app-name>` directory explaining the purpose and configuration of the app, and exclude it from ArgoCD sync.

## 🔗 Reference Documentation
- [ArgoCD Official Docs](https://argo-cd.readthedocs.io/)
- [ArgoCD Directory Source Guide](https://oneuptime.com/blog/post/2026-02-26-argocd-include-exclude-files-directory/view)
- [Multi-Source Strategy](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/)
