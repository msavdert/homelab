# Metrics Server

Scalable, efficient source of container resource metrics for Kubernetes built-in autoscaling.

## 1. Installation Details
- **Method:** ArgoCD / Kustomize (Helm Inflation).
- **Source:** [metrics-server/metrics-server](https://kubernetes-sigs.github.io/metrics-server/)
- **Version:** `v0.7.1` (Chart `3.12.1`)
  - *Determination:* Standard stable release for K8s 1.30 compatibility.
- **Sync Wave:** `2`

## 2. Configuration Rationale
- **Insecure TLS:** Enabled via `--kubelet-insecure-tls`.
  - *Reason:* Talos Linux Kubelets use self-signed certificates. Without this flag, Metrics Server cannot scrape resource data.
- **Resources:** Configured with specific requests/limits to ensure predictable performance in a homelab environment.

## 3. References
- [GitHub Repository](https://github.com/kubernetes-sigs/metrics-server)
- [Talos Linux Metrics Guide](https://www.talos.dev/v1.7/kubernetes-guides/configuration/metrics-server/)
