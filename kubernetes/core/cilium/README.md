# Cilium CNI Deployment

This directory manages the configuration for **Cilium**, the eBPF-powered Networking, Observability, and Security layer for our Kubernetes cluster.

## Deployment Strategy

We use a two-stage deployment strategy to ensure a stable and manageable networking stack.

### 1. Minimal Bootstrap (Terraform)
Since we are running on **Talos Linux**, a CNI must be present for nodes to reach a `Ready` state. We use Terraform to render a minimal Cilium manifest and inject it into the Talos machine configuration during the initial bootstrap.

- **Source**: `infrastructure/terraform/talos.tf`
- **Purpose**: Provides basic connectivity so that ArgoCD and other core components can start.
- **Key Settings**:
    - `ipam.mode: kubernetes`
    - `kubeProxyReplacement: true`
    - Specific security contexts for Talos compatibility.

### 2. GitOps Management (ArgoCD)
Once the cluster is bootstrapped and ArgoCD is running, the management of Cilium is handed over to ArgoCD. This allows us to enable advanced features declaratively and manage upgrades safely.

- **AppSet**: `kubernetes/argocd-apps/core-appset.yaml`
- **Values**: `kubernetes/core/cilium/values.yaml`

#### Advanced Features Enabled via ArgoCD:
- **Hubble**: Network observability (UI and Relay).
- **Gateway API**: Modern Kubernetes ingress management (Primary solution).
- **L2 Announcements (v2alpha1)**: L2 advertisement for LoadBalancer IPs.
- **Performance Tuning**: Optimized client rate limits for CRD stability.

## ArgoCD Best Practices & Compatibility

To ensure Cilium works smoothly with ArgoCD (especially on Talos), several best practices have been implemented based on the [official Cilium troubleshooting guide](https://docs.cilium.io/en/latest/configuration/argocd-issues/):

### Server-Side Apply
We use `ServerSideApply=true` in the ArgoCD sync options. This is critical for Cilium because:
- It handles large CRDs that might exceed the annotation size limit of `kubectl apply`.
- It resolves schema conflicts with Talos's `appArmorProfile` field.

### Resource Exclusions
We have configured `argocd-cm` (in `kubernetes/bootstrap/kustomization.yaml`) to exclude `CiliumIdentity` resources.
```yaml
resource.exclusions: |
  - apiGroups:
    - cilium.io
    kinds:
    - CiliumIdentity
    clusters:
    - "*"
```
*Why?* Cilium generates identities dynamically. If ArgoCD tries to manage or prune them, it can cause cluster-wide networking outages.

### Ignoring Hubble Certificate Drift
Hubble certificates are non-idempotent (they may be regenerated and cause drift). We use `nonIdempotentAnnotations` in `values.yaml` to tell ArgoCD to ignore these differences:
```yaml
nonIdempotentAnnotations:
  argocd.argoproj.io/compare-options: IgnoreExtraneous
```

## References
- [Cilium Troubleshooting: ArgoCD Issues](https://docs.cilium.io/en/latest/configuration/argocd-issues/)
- [Talos Linux: Cilium Installation](https://docs.cilium.io/en/stable/installation/talos/)
