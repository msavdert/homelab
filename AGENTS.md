# AI Agent Instructions for GitOps & ArgoCD Architecture

Hello AI Agent. When generating, modifying, or refactoring Kubernetes manifests and ArgoCD Application/ApplicationSet resources in this repository, you MUST strictly adhere to the following architectural rules and best practices.

## 1. Core Architecture Context
- **Infrastructure:** Proxmox VE, Talos OS (4 nodes), Cilium CNI (Kube-proxy replacement mode).
- **GitOps Tool:** ArgoCD v3.x+ managing a "Server-Side Apply" heavy environment.
- **Storage:** Longhorn (Strictly `replicaCount: 1` and `defaultDataLocality: disabled`).
- **Secrets:** External Secrets Operator (ESO) backed by 1Password. NEVER output raw secrets or `Secret` manifests containing plaintext data.

## 2. ArgoCD Sync Policies & Options
Do NOT blindly apply the same sync policies to every application. Use the following context-aware rules:

### A. Core Infrastructure & Networking (Cilium, Cert-Manager, Prometheus)
CRD-heavy applications MUST use `ServerSideApply=true` to prevent "metadata too long" errors.
```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true # MANDATORY for CRDs