# GitOps Architecture & Sync Strategy

This document outlines the advanced GitOps architecture implemented in this repository, following production-grade best practices for Talos Linux and ArgoCD environments.

## 1. Directory Structure

The repository follows a hierarchical structure to separate infrastructure concerns:

- `kubernetes/bootstrap/`: Initial ArgoCD installation and global cluster configurations.
- `kubernetes/argocd-apps/`: Root Application and ApplicationSet definitions.
- `kubernetes/core/`: Core infrastructure components (Cilium, Longhorn, Cert-Manager, etc.).
- `kubernetes/apps/`: User-facing applications and services.

## 2. Dependency Management & Sync Waves

To solve the "chicken-and-egg" problem of cluster bootstrapping (e.g., needing storage before databases), we use **ArgoCD Sync Waves**.

### Wave Strategy

Applications are categorized into waves to ensure a deterministic boot sequence:

| Wave | Component | Responsibility |
|------|-----------|----------------|
| **0** | `cilium`, `external-secrets` | Network connectivity and secret management. |
| **1** | `longhorn` | Persistent storage layer. |
| **2** | `cert-manager`, `tailscale`, `metrics-server` | Connectivity, certificates, and metrics. |
| **3** | `cnpg` | Database operators. |
| **5+** | User Applications | Business workloads and dashboards. |

### Metadata-Driven Discovery

We use a "Smart ApplicationSet" approach. Instead of a simple directory glob, the `core-infrastructure` ApplicationSet uses a **Git Files Generator**.

Each component in `kubernetes/core/*/` contains a `metadata.json` file:
```json
{
  "wave": "1"
}
```
The ApplicationSet reads this file and automatically injects the `argocd.argoproj.io/sync-wave` annotation into the generated Application resource. This decouples the deployment logic from the folder structure.

## 3. ArgoCD Customizations

To enable reliable inter-application dependencies, several global customizations are applied in `kubernetes/bootstrap/argocd-cm`:

### Application Health Check (Lua)
Standard ArgoCD marks a parent "Healthy" as soon as a child Application resource is created. We have injected a custom Lua health check that forces parent applications (like the Root App) to wait until the child application's **actual resources** (Pods, Deployments) are Healthy.

### Server-Side Diff & Apply
- **Server-Side Apply (SSA)**: Used for all core components to handle large CRDs and field ownership.
- **Server-Side Diff**: Enabled globally to prevent "false" Out-Of-Sync states caused by Kubernetes defaults or mutating webhooks.

### Global IgnoreDifferences
Common drift-heavy fields are ignored globally to maintain a "Green" dashboard:
- MutatingWebhookConfiguration `caBundle`
- StatefulSet `volumeClaimTemplates`
- CustomResourceDefinition `labels` and `conversion`

## 4. Database & Storage Best Practices

For database workloads (e.g., CloudNativePG), we follow high-performance storage patterns to avoid write amplification on Longhorn:

- **Dedicated StorageClass (`longhorn-db`)**: 
  - `replicaCount: 1`: Since databases like CNPG handle their own replication at the application level, we reduce storage replication to 1.
  - `dataLocality: strict-local`: Ensures that the volume's data always resides on the same node as the Pod for minimum latency.
- **ArgoCD `RespectIgnoreDifferences`**: Enabled globally to allow the CNPG operator to manage status fields and certificates without triggering ArgoCD sync loops.

## 5. Best Practices for New Apps

When adding a new core component:
1. Create the folder in `kubernetes/core/<name>`.
2. Add a `metadata.json` with the appropriate `wave`.
3. Ensure the folder name matches the intended `namespace` for consistency with the ApplicationSet's `destination.namespace` template.
