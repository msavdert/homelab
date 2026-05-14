# Grafana Operator

Manages the lifecycle of Grafana instances and their configurations (Dashboards, Datasources) via Kubernetes CRDs.

## 1. Overview
Instead of traditional Helm-based Grafana deployments, we use the Grafana Operator to treat dashboards and datasources as GitOps-friendly resources.

## 2. Installation Details
- **Method:** ArgoCD / Kustomize (OCI Helm Chart).
- **Source:** `oci://ghcr.io/grafana/helm-charts/grafana-operator`
- **Version:** `5.22.2`
- **Sync Wave:** `6`

## 3. Configuration Rationale
- **OCI Chart:** Using the official OCI-based distribution as per 2026 best practices.
- **GitOps Ready:** Allows defining `GrafanaDashboard` and `GrafanaDatasource` objects in any namespace, which the operator will automatically discover.

## 4. References
- [Grafana Operator GitHub](https://github.com/grafana/grafana-operator)
- [OCI Helm Charts Guide](https://helm.sh/docs/topics/registries/)
