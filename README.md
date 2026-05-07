# Homelab: Proxmox & Talos Linux GitOps Cluster

This repository contains the Infrastructure-as-Code (Terraform) and Kubernetes manifests for a modern homelab hosted on a Hetzner dedicated server.

## Architecture

- **Hypervisor**: Proxmox VE 9.x (Level 0)
- **OS**: Talos Linux (Level 1)
- **Networking**: Cilium (CNI, LoadBalancer, Ingress)
- **GitOps**: ArgoCD (Level 2)
- **Storage**: Longhorn (Level 3)

---

## Getting Started: Post-Infrastructure Setup

Once the Proxmox installation and Terraform (`terraform apply`) are complete, follow these steps to bootstrap the cluster.

### 1. Verify Connectivity
Ensure your `KUBECONFIG` is pointing to the new cluster and nodes are `Ready`.
```bash
export KUBECONFIG=./terraform/kubeconfig
kubectl get nodes
```

### 2. Bootstrap ArgoCD (Manual Deployment)
We use Kustomize to install ArgoCD with best-practice configurations.
```bash
# Apply the bootstrap manifests
kubectl apply -k kubernetes/bootstrap/argocd
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

### 4. Initialize GitOps (The Root App)
Once ArgoCD is running, apply the Root Application to start the "App-of-Apps" sync:
```bash
kubectl apply -f kubernetes/bootstrap/argocd/root-app.yaml
```

---

## References

- [Proxmox Setup Guide](docs/proxmox-setup.md)
- [Project Roadmap](docs/ROADMAP.md)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/en/stable/)
- [Talos Linux Documentation](https://www.talos.dev/)
- [Cilium Documentation](https://docs.cilium.io/)
