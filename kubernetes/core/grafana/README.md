# Grafana Instance

A managed Grafana deployment via Grafana Operator, integrated with VictoriaMetrics and External Secrets.

## 1. Overview
This instance is the primary visualization engine for the homelab. It is configured to automatically discover dashboards and datasources via Kubernetes labels.

## 2. Infrastructure Details
- **Sync Wave:** `8`
- **Persistence:** 5Gi volume on `longhorn-db` (strict-local).
- **Access:** Exposed via Tailscale Ingress at `https://grafana.<tailnet-name>.ts.net`.
- **Default Datasource:** VictoriaMetrics (`http://vmsingle-vm-shared.monitoring.svc:8429`).

## 3. Secret Management (ESO)
The admin credentials are NOT managed via plain YAML. We use **External Secrets Operator (ESO)** to fetch them from Infisical.

### Required Infisical Keys:
- `GRAFANA_ADMIN_USER`: The username for the admin account.
- `GRAFANA_ADMIN_PASSWORD`: The secure password for the admin account.

The `ExternalSecret` resource in this directory maps these remote keys to a local Kubernetes secret named `grafana-admin-credentials`, which the Grafana resource then consumes.

## 4. Operational Best Practices
- **Dashboards:** Add the label `grafana_dashboard: "true"` to any `ConfigMap` containing a JSON dashboard to have the operator automatically import it.
- **HA:** This instance is a single pod because persistence is handled via Longhorn `strict-local`.

## 5. References
- [Grafana Operator Resources](https://grafana-operator.github.io/grafana-operator/docs/grafana/)
- [Tailscale Ingress Guide](https://tailscale.com/kb/1236/kubernetes-ingress/)
