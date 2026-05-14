# Installation Guide

Step-by-step deployment of the full observability stack on a Talos Kubernetes cluster.

## Prerequisites

Before starting, verify:

```bash
# ArgoCD is running
kubectl get pods -n argocd

# 1Password Operator is running
kubectl get pods -n onepassword

# cert-manager is running (required by OTel Operator webhooks)
kubectl get pods -n cert-manager

# Longhorn is running (used by other apps, not monitoring)
kubectl get pods -n longhorn-system

# local-path provisioner is available
kubectl get storageclass local-path
```

If `local-path` is not available:

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
```

## Step 1: Apply Talos eBPF Patch

This step is required for Beyla to function. It configures kernel parameters and
adds a PSA exemption for the `observability` namespace.

```bash
# Apply to all worker nodes
talosctl patch machineconfig \
  --patch @talos/beyla-ebpf-patch.yaml \
  --nodes <worker-1-ip>,<worker-2-ip>,<worker-3-ip>
```

Talos will reboot each node sequentially. Wait for all nodes to become healthy:

```bash
talosctl health \
  --nodes <worker-1-ip>,<worker-2-ip>,<worker-3-ip>
```

Verify the kernel parameters were applied:

```bash
talosctl read /proc/sys/kernel/perf_event_paranoia --nodes <worker-1-ip>
# Expected: 1

talosctl read /proc/sys/net/core/bpf_jit_enable --nodes <worker-1-ip>
# Expected: 1
```

## Step 2: Create 1Password Items

Create the following items in the `homelab` vault in 1Password before deploying.
The 1Password Operator will sync them into Kubernetes Secrets.

### grafana-admin-credentials

| Field | Value |
|-------|-------|
| `username` | `admin` |
| `password` | (choose a strong password) |

### clickhouse-admin-credentials

| Field | Value |
|-------|-------|
| `username` | `admin` |
| `password` | (choose a strong password) |

This secret is used by:
- The Altinity Operator to set the ClickHouse `admin` user password
- The OTel Gateway to authenticate as `otel_writer`
- The `clickhouse-otel-init` Job to create the `otel` database

## Step 3: Commit and Push

All ArgoCD Applications are already defined in `apps/production/`. Push to trigger
the app-of-apps sync:

```bash
git add .
git commit -m "feat: add OTel-native dual-target observability stack"
git push
```

ArgoCD will sync automatically. The sync wave ordering guarantees correct deployment
sequence:

```
wave -10: cilium, longhorn, gateway-api-crds
wave  -8: cert-manager, onepassword
wave  -5: clickhouse-operator, grafana-operator, tempo-operator, observability-operator
wave  -4: victoriametrics, loki, tempo (TempoMonolithic CR)
wave  -3: clickhouse, grafana (Grafana + GrafanaDatasource CRs), observability
```

## Step 4: Monitor Deployment Progress

```bash
# Watch all applications
watch kubectl get applications -n argocd

# Watch pods coming up
watch kubectl get pods -n observability
watch kubectl get pods -n monitoring
watch kubectl get pods -n clickhouse
```

Expected final state:

```
NAMESPACE       NAME                                    READY   STATUS
observability   otel-agent-collector-<hash>-<node1>    1/1     Running
observability   otel-agent-collector-<hash>-<node2>    1/1     Running
observability   otel-agent-collector-<hash>-<node3>    1/1     Running
observability   otel-gateway-collector-<hash>           1/1     Running
observability   beyla-<hash>-<node1>                    1/1     Running
observability   beyla-<hash>-<node2>                    1/1     Running
observability   beyla-<hash>-<node3>                    1/1     Running
observability   opentelemetry-operator-<hash>           1/1     Running

monitoring      victoriametrics-<hash>                  1/1     Running
monitoring      loki-0                                  1/1     Running
monitoring      tempo-monolithic-<hash>                 1/1     Running   ← TempoMonolithic CR
monitoring      grafana-deployment-<hash>               1/1     Running   ← Grafana CR
monitoring      grafana-operator-<hash>                 1/1     Running
monitoring      tempo-operator-<hash>                   1/1     Running

clickhouse      clickhouse-clickhouse-0-0-0             1/1     Running
clickhouse      clickhouse-operator-<hash>              1/1     Running
```

## Step 5: Verify Data Flow

### Verify OTel Agent is collecting

```bash
# Check Agent logs for collection activity
kubectl logs -n observability \
  -l app.kubernetes.io/name=otel-agent-collector \
  --tail=20 | grep -v "health_check"
```

Look for lines like:
```
Exporting items count=42 signal=metrics
Exporting items count=15 signal=logs
```

### Verify Gateway is receiving and forwarding

```bash
kubectl logs -n observability \
  -l app.kubernetes.io/name=otel-gateway-collector \
  --tail=30
```

Look for successful exports to VictoriaMetrics, Loki, Tempo, and ClickHouse.

### Verify VictoriaMetrics is receiving metrics

```bash
kubectl port-forward -n monitoring svc/victoriametrics 8428:8428 &
curl -s "http://localhost:8428/api/v1/query?query=up" | python3 -m json.tool | head -20
```

Or open `http://localhost:8428/vmui` and query `k8s_pod_memory_working_set_bytes`.

### Verify Loki is receiving logs

```bash
kubectl port-forward -n monitoring svc/loki 3100:3100 &
curl -s "http://localhost:3100/loki/api/v1/labels" | python3 -m json.tool
```

Should return labels including `namespace`, `pod`, `deployment`.

### Verify ClickHouse is receiving data

```bash
CH_POD=$(kubectl get pod -n clickhouse \
  -l clickhouse.altinity.com/chi=clickhouse \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n clickhouse $CH_POD -- \
  clickhouse-client --user admin --password "$CH_PASS" \
  --query "
    SELECT 'logs' AS signal, count() AS rows FROM otel.otel_logs
    UNION ALL
    SELECT 'traces', count() FROM otel.otel_traces
    UNION ALL
    SELECT 'metrics_gauge', count() FROM otel.otel_metrics_gauge
    FORMAT PrettyCompact"
```

### Verify Beyla is instrumenting services

```bash
# Check Beyla logs for attached probes
kubectl logs -n observability \
  -l app.kubernetes.io/name=beyla \
  --tail=30 | grep -i "instrument\|attach"

# Query VictoriaMetrics for Beyla RED metrics
kubectl port-forward -n monitoring svc/victoriametrics 8428:8428 &
curl -s "http://localhost:8428/api/v1/query?query=http_server_request_duration_seconds_count" \
  | python3 -m json.tool | grep "metric" | head -10
```

## Step 6: Configure Grafana

1. Open `https://grafana.savdert.com`
2. Log in with credentials from 1Password (`grafana-admin-credentials`)
3. Verify data sources are connected: **Configuration → Data Sources**
   - VictoriaMetrics: click "Test" → should show "Data source is working"
   - Loki: click "Test" → should show "Data source connected and labels found"
   - Tempo: click "Test" → should show "Data source is working"

   > **Note:** Datasources are managed by the Grafana Operator via `GrafanaDatasource`
   > CRDs. They are synced automatically — no manual configuration needed.

4. Add dashboards via GitOps — create `GrafanaDashboard` CRs in
   `apps/base/monitoring/grafana/`:

```yaml
# Example: apps/base/monitoring/grafana/dashboard-kubernetes.yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: kubernetes-cluster
  namespace: monitoring
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  grafanaCom:
    id: 17119
    revision: 2
```

Commit and push — ArgoCD syncs the dashboard into Grafana automatically.

## Updating Component Versions

All Helm chart versions are pinned and managed by Renovate. To update manually:

1. Change `targetRevision` in the relevant `apps/production/*.yaml` file
2. Commit and push — ArgoCD syncs automatically

For the OTel Operator, always check the
[changelog](https://github.com/open-telemetry/opentelemetry-operator/blob/main/CHANGELOG.md)
for breaking changes to the `OpenTelemetryCollector` CRD before upgrading.

For the Altinity Operator, always upgrade the operator (`clickhouse-operator`) before
upgrading the ClickHouse image version in `clickhouse-installation.yaml`.
