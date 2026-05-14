# Shared PostgreSQL Cluster

Production-grade HA PostgreSQL cluster managed by CloudNativePG (CNPG), serving as the central database backend for the cluster.

## 1. Overview
The `postgres-shared` cluster is a high-availability Postgres deployment using the Shared-Nothing architecture.

## 2. Operator Details
- **Operator:** CloudNativePG (CNPG)
- **Version:** `v1.29.1` (Chart `0.28.2`)
  - *Determination:* Latest stable release from [cloudnative-pg.github.io/charts](https://cloudnative-pg.github.io/charts).
- **Sync Wave:** `3` (Operator).

## 3. Instance Details
- **Name:** `postgres-shared`
- **Sync Wave:** `5` (Applied after operator and storage are ready).
- **Instances:** `3` (1 Primary, 2 Replicas).

## 4. Architecture & Performance (Best Practices)
- **High Availability:** Pod Anti-Affinity is enabled to ensure pods are scheduled on different nodes.
- **Storage Strategy:**
  - **PGDATA:** `20Gi` on `longhorn-db` StorageClass (Replica: 1, strict-local).
  - **WAL Volume:** `10Gi` dedicated volume for Write-Ahead Logs. This separates sequential I/O (WAL) from random I/O (Data), a critical DB performance practice.
- **Tuning:** `random_page_cost` set to `1.1` to optimize for SSD/NVMe backed storage.

## 5. Security & Secrets
- **Credentials:** Managed by CNPG. System credentials can be found in the `postgres-shared-app` secret.
- **Images:** Pinned to specific versions (e.g., `16.4`) to satisfy Renovate requirements.

## 6. References
- [CNPG Storage Guide](https://cloudnative-pg.io/docs/1.29/storage/)
- [ArgoCD Implementation Example](https://github.com/sxd/cloudnative-pg-argocd/)
