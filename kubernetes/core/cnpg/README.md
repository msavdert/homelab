# CloudNativePG Operator

The CloudNativePG (CNPG) operator manages the full lifecycle of PostgreSQL clusters on Kubernetes.

## 1. Overview
CNPG is a Kubernetes-native operator that replaces traditional PostgreSQL HA solutions (like Patroni) by leveraging Kubernetes primitives for replication and failover.

## 2. Installation Details
- **Method:** ArgoCD / Kustomize (Helm Inflation).
- **Source:** [cloudnative-pg.github.io/charts](https://cloudnative-pg.github.io/charts)
- **Version:** `v1.29.1` (Chart `0.28.2`)
  - *Determination:* Checked via `helm search repo cnpg` for the latest stable 1.29.x operator.
- **Namespace:** `cnpg-system`
- **Sync Wave:** `3` (Depends on networking and storage availability).

## 3. Configuration Rationale
- **Monitoring (`podMonitorEnabled: false`):** Temporarily disabled because the Prometheus Operator CRDs (PodMonitor) are not yet installed in the cluster. Will be enabled once the observability stack is ready.
- **CRD Management:** `crds.enabled: true` is set in Helm values to ensure the operator's CRDs are deployed and updated during Helm lifecycle.
- **Global Reach:** The operator is installed in `cnpg-system` but watches all namespaces for `Cluster` resources.

## 4. Key Responsibilities
- Automated failover and recovery.
- Declarative management of PostgreSQL clusters.
- WAL management and backup orchestration.
- Integration with Kubernetes-native storage (e.g., Longhorn).

## 5. References
- [Official Documentation](https://cloudnative-pg.io/docs/1.29/)
- [Release Notes](https://github.com/cloudnative-pg/cloudnative-pg/releases)
