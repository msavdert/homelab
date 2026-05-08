# Homelab: Proxmox & Talos Linux GitOps Cluster

This repository contains the Infrastructure-as-Code (Terraform) and Kubernetes manifests for a modern homelab hosted on a Hetzner dedicated server.

## Architecture

- **Hypervisor**: Proxmox VE 9.x (Level 0)
- **OS**: Talos Linux (Level 1)
- **Networking**: Cilium (CNI, LoadBalancer, Ingress)
- **GitOps**: ArgoCD (Level 2)
- **Storage**: Longhorn (Level 3)

---

```text
.
├── infrastructure/
│   └── terraform/             # Proxmox and Talos code
└── kubernetes/
    ├── bootstrap/             # 1. Initial manifests that install ArgoCD
    ├── argocd-apps/           # 2. ApplicationSet definitions
    │   ├── core-appset.yaml   # Auto-discovers everything in /kubernetes/core/
    │   └── apps-appset.yaml   # Auto-discovers everything in /kubernetes/apps/
    ├── core/                  # 3. Infrastructure services (System)
    │   ├── cilium/            # Networking & Ingress (Helm + Kustomize)
    │   ├── longhorn/          # Storage
    │   ├── external-secrets/  # Secret Management (1Password)
    │   └── tailscale/         # VPN Ingress
    └── apps/                  # 4. User projects and services
        └── homelab-dashboard/
```

### GitOps Methodology (2026 Edition)

#### 1. "App of Apps" is Dead, Long Live "ApplicationSets"
Historically, we used a single "Root" Application to manage others. Today, we use **ApplicationSets** with Git Directory Generators. Adding a tool to `/kubernetes/core/` now automatically triggers a deployment without writing extra ArgoCD manifests, making the repo DRY and dynamic.



#### 2. Server-Side Apply (SSA)
Modern tools like Cilium and Prometheus have massive CRDs. ArgoCD's traditional client-side apply often fails with "Metadata too long" errors. **ServerSideApply=true** is now a requirement for modern infrastructure.



#### 3. Helm & Kustomize: The Perfect Marriage
We use "Helm Inflation" via Kustomize. We pull the official Helm chart from upstream and apply environment-specific patches (like `replicas: 1`) using Kustomize. This keeps our repo clean and allows Renovate to automate updates easily.




## Getting Started: Post-Infrastructure Setup

Once the Proxmox installation and Terraform (`terraform apply`) are complete, follow these steps to bootstrap the cluster.

### 1. Verify Connectivity
Ensure your `KUBECONFIG` is pointing to the new cluster and nodes are `Ready`.
```bash
export KUBECONFIG=./infrastructure/terraform/kubeconfig
kubectl get nodes
```

### 2. Bootstrap ArgoCD (Manual Deployment)
We use Kustomize to install ArgoCD with best-practice configurations. 

> [!IMPORTANT]
> Since ArgoCD CRDs are large, you MUST use Server-Side Apply to avoid "annotation too long" errors.

```bash
# Apply the bootstrap manifests with server-side apply
kubectl apply -k kubernetes/bootstrap --server-side --force-conflicts
```

### 3. Access ArgoCD UI
ArgoCD is currently not exposed externally. Use `port-forward` to access it locally:
```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```
Now access the UI at [https://localhost:8080](https://localhost:8080).

**Initial Credentials:**
- **Username**: `admin`
- **Password**: Retrieve with the following command:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
  ```

### 4. Wait for Sync
Once you apply the bootstrap kustomization, ArgoCD will install itself and then pick up the ApplicationSet definitions. It will automatically start discovering and deploying applications in `kubernetes/core/` and `kubernetes/apps/`.

Check the status in the UI or via:
```bash
kubectl -n argocd get applicationsets
kubectl -n argocd get applications
```

---

## Maintenance & Updates

We use **Renovate Bot** to automate dependency updates across the entire stack.

### How it works:
1. **Scanning**: Renovate scans the repo for Terraform providers, Kubernetes manifests, and Helm charts.
2. **Grouping**: Minor and patch updates are grouped to reduce PR noise.
3. **Automated PRs**: Renovate opens Pull Requests for available updates.
4. **Automerge**: Minor and patch updates are automatically merged if they pass CI/CD checks (if configured). Major updates always require manual review.

### Setup:
1. Install the [Renovate GitHub App](https://github.com/apps/renovate).
2. Grant access to this repository.
3. Merge the onboarding PR.

---

## References

- [Proxmox Setup Guide](docs/proxmox-setup.md)
- [Project Roadmap](docs/ROADMAP.md)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/en/stable/)
- [Talos Linux Documentation](https://www.talos.dev/)
- [Cilium Documentation](https://docs.cilium.io/)
