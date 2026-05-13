# LGTM Stack

The LGTM stack is the primary observability system. It stores production telemetry
with long retention and provides the Grafana UI for dashboards and alerting.

## Components and Deployment Model

| Component | Deployment Model | Retention |
|-----------|-----------------|-----------|
| VictoriaMetrics | Standalone Helm chart | 90 days |
| Loki | Standalone Helm chart | 31 days |
| Tempo | **Tempo Operator** (`TempoMonolithic` CR) | 14 days |
| Grafana | **Grafana Operator** (`Grafana` + `GrafanaDatasource` CRs) | — |

**Why operators for Grafana and Tempo, but not for Loki and VictoriaMetrics?**

- **Grafana Operator** — enables GitOps management of dashboards, datasources, and
  alert rules as Kubernetes CRDs (`GrafanaDashboard`, `GrafanaDatasource`). This is
  the primary value: datasources are version-controlled and auto-synced, not manually
  configured in the UI.

- **Tempo Operator** — manages `TempoMonolithic` CRD with proper lifecycle management,
  cert rotation, and upgrade handling. Tempo v2.10.0 is managed by operator v0.20.0.

- **Loki Operator** — requires S3-compatible object storage for `LokiStack`. It does
  not support the filesystem backend. The standalone Helm chart with
  `deploymentMode: SingleBinary` is the correct approach for this homelab.

- **VictoriaMetrics Operator** — adds value for multi-component cluster deployments.
  For a single-node `victoria-metrics-single`, the standalone chart is simpler.

All components run in the `monitoring` namespace and use `local-path` StorageClass.

---

## VictoriaMetrics

**Chart:** `victoriametrics/victoria-metrics-single` v0.37.0
**ArgoCD Application:** `apps/production/victoriametrics.yaml`

VictoriaMetrics is a drop-in replacement for Prometheus with better compression,
faster queries, and simpler operation. It accepts Prometheus remote write at
`/api/v1/write` — the same endpoint the OTel Gateway's `prometheusremotewrite`
exporter targets.

### Key Configuration

```yaml
server:
  retentionPeriod: 90d
  persistentVolume:
    storageClass: local-path
    size: 30Gi
  extraArgs:
    dedup.minScrapeInterval: 30s
```

`dedup.minScrapeInterval: 30s` deduplicates metrics that arrive from multiple sources
within a 30-second window. This is useful if both the OTel Agent and Beyla send the
same metric for the same service.

### Remote Write Endpoint

The OTel Gateway writes to:
```
http://victoriametrics.monitoring.svc.cluster.local:8428/api/v1/write
```

Tempo's metrics generator also writes RED metrics to this endpoint.

### Accessing VictoriaMetrics UI

```bash
kubectl port-forward -n monitoring svc/victoriametrics 8428:8428
# http://localhost:8428/vmui
```

Or via Cloudflare Tunnel: `https://victoriametrics.savdert.com`

### Useful MetricsQL Queries

```promql
# All metrics from a specific namespace
{k8s_namespace_name="default"}

# HTTP request rate by deployment (from Beyla)
rate(http_server_request_duration_seconds_count{k8s_deployment_name!=""}[5m])

# Node CPU utilization
system_cpu_utilization{state="user"}

# Pod memory working set
k8s_pod_memory_working_set_bytes

# Top 10 pods by CPU
topk(10, rate(k8s_container_cpu_usage_nanoseconds_total[5m]))
```

---

## Loki

**Chart:** `grafana-community/loki` v13.5.0
**ArgoCD Application:** `apps/production/loki.yaml`

> **Note:** As of March 2026, the Loki Helm chart moved from `grafana/helm-charts`
> to `grafana-community/helm-charts`. The chart is now community-maintained.

Loki stores logs in a compressed, label-indexed format. It only indexes stream labels
(namespace, pod, deployment) — full-text search uses grep-style scanning over
compressed chunks.

### Key Configuration

```yaml
loki:
  auth_enabled: false
  limits_config:
    retention_period: 744h   # 31 days
    ingestion_rate_mb: 16
    ingestion_burst_size_mb: 32
    per_stream_rate_limit: 10MB
```

`auth_enabled: false` disables multi-tenancy. With it enabled, all requests require
an `X-Scope-OrgID` header, which causes "Unable to connect" errors in Grafana.

### Stream Labels

The OTel Gateway's Loki exporter maps these resource attributes to Loki stream labels:

| OTel Attribute | Loki Label |
|----------------|-----------|
| `k8s.namespace.name` | `namespace` |
| `k8s.pod.name` | `pod` |
| `k8s.container.name` | `container` |
| `k8s.node.name` | `node` |
| `k8s.deployment.name` | `deployment` |
| `app.kubernetes.io/name` | `app` |
| `k8s.cluster.name` | `cluster` |

### LogQL Queries in Grafana

```logql
# All logs from a namespace
{namespace="default"}

# Error logs from a specific app
{app="checkout"} | json | level="error"

# Logs containing a specific string
{namespace="default"} |= "payment failed"

# Log volume over time
sum(count_over_time({namespace="default"}[5m])) by (app)
```

---

## Tempo (via Tempo Operator)

**Operator Chart:** `grafana/tempo-operator` v0.20.0 (manages Tempo v2.10.0)
**ArgoCD Applications:**
- `apps/production/tempo-operator.yaml` — installs the operator (wave -5)
- `apps/production/tempo.yaml` — deploys the `TempoMonolithic` CR (wave -4)

**CR manifest:** `apps/base/monitoring/tempo/tempo.yaml`

### TempoMonolithic CR

The `TempoMonolithic` CRD deploys Tempo as a single binary (all components in one pod).
This is the correct mode for a homelab — no distributed components, no S3 required.

```yaml
apiVersion: tempo.grafana.com/v1alpha1
kind: TempoMonolithic
metadata:
  name: tempo-monolithic
  namespace: monitoring
spec:
  storage:
    traces:
      backend: pv
      pv:
        size: 15Gi
        storageClassName: local-path
  ingestion:
    otlp:
      grpc:
        enabled: true
        tls:
          enabled: false
  retention:
    global:
      tracesMaxAge: 336h   # 14 days
```

The operator creates a Service named `tempo-monolithic` in the `monitoring` namespace.
The OTel Gateway sends traces to `tempo-monolithic.monitoring.svc.cluster.local:4317`.

### Metrics Generator

The `tempo-config.yaml` ConfigMap adds the metrics generator configuration that
derives RED metrics from traces and pushes them to VictoriaMetrics:

```yaml
metrics_generator:
  storage:
    remote_write:
      - url: http://victoriametrics.monitoring.svc.cluster.local:8428/api/v1/write
  processor:
    service_graphs:
      enabled: true
    span_metrics:
      enabled: true
```

### TraceQL Queries in Grafana

```traceql
# All traces from a service
{resource.service.name="checkout"}

# Error traces
{status=error}

# Slow traces (> 1 second)
{duration > 1s}

# Traces from a specific namespace
{resource.k8s.namespace.name="default"}
```

---

## Grafana (via Grafana Operator)

**Operator Chart:** `oci://ghcr.io/grafana/helm-charts/grafana-operator` v5.22.2
**ArgoCD Applications:**
- `apps/production/grafana-operator.yaml` — installs the operator (wave -5)
- `apps/production/grafana.yaml` — deploys Grafana CRs (wave -3)

**CR manifests:** `apps/base/monitoring/grafana/`

### Why the Grafana Operator?

The Grafana Operator enables full GitOps management of Grafana resources:

| CRD | Purpose |
|-----|---------|
| `Grafana` | The Grafana instance itself (deployment, storage, ingress) |
| `GrafanaDatasource` | Data sources — version-controlled, auto-synced |
| `GrafanaDashboard` | Dashboards — import from URL, ConfigMap, or inline JSON |
| `GrafanaAlertRuleGroup` | Alert rules as code |
| `GrafanaContactPoint` | Notification channels |

Datasources are defined in `apps/base/monitoring/grafana/datasources.yaml` as
`GrafanaDatasource` CRs. The operator syncs them to Grafana via the HTTP API —
no manual configuration in the UI needed.

### Grafana CR

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: Grafana
metadata:
  name: grafana
  namespace: monitoring
  labels:
    dashboards: grafana   # GrafanaDatasource instanceSelector matches this
spec:
  deployment:
    spec:
      template:
        spec:
          containers:
            - name: grafana
              env:
                - name: GF_SECURITY_ADMIN_USER
                  valueFrom:
                    secretKeyRef:
                      name: grafana-admin-credentials
                      key: username
                - name: GF_SECURITY_ADMIN_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: grafana-admin-credentials
                      key: password
  persistentVolumeClaim:
    spec:
      storageClassName: local-path
      resources:
        requests:
          storage: 5Gi
  ingress:
    spec:
      ingressClassName: cilium
      rules:
        - host: grafana.savdert.com
```

### Admin Credentials

Admin credentials are managed by 1Password:

```yaml
# apps/base/monitoring/grafana/onepassword-items.yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: grafana-admin-credentials
  namespace: monitoring
spec:
  itemPath: "vaults/homelab/items/grafana-admin-credentials"
```

The `grafana-admin-credentials` Secret is synced from 1Password and injected into
the Grafana pod via `GF_SECURITY_ADMIN_USER` and `GF_SECURITY_ADMIN_PASSWORD` env vars.

### GrafanaDatasource CRs

All three datasources are defined as CRs in `apps/base/monitoring/grafana/datasources.yaml`:

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDatasource
metadata:
  name: victoriametrics
  namespace: monitoring
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana   # targets the Grafana CR with this label
  datasource:
    name: VictoriaMetrics
    type: prometheus
    uid: victoriametrics
    url: http://victoriametrics.monitoring.svc.cluster.local:8428
    isDefault: true
```

The `instanceSelector.matchLabels` must match the `metadata.labels` on the `Grafana` CR.

### Adding Dashboards via GitOps

With the Grafana Operator, dashboards can be managed as CRDs:

```yaml
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
    id: 17119        # Import from grafana.com by ID
    revision: 2
```

Add dashboard CRs to `apps/base/monitoring/grafana/` and they will be automatically
imported into Grafana on the next ArgoCD sync.

### Ingress

```yaml
ingress:
  metadata:
    annotations:
      ingress.cilium.io/loadbalancer-mode: shared
  spec:
    ingressClassName: cilium
    rules:
      - host: grafana.savdert.com
```

The existing Cloudflare Tunnel wildcard (`*.savdert.com`) picks up this ingress
automatically.

### Suggested Dashboards to Add

Add these as `GrafanaDashboard` CRs in `apps/base/monitoring/grafana/`:

| Dashboard | grafana.com ID | Description |
|-----------|---------------|-------------|
| Kubernetes / Compute Resources / Cluster | 17119 | Cluster-wide CPU/memory |
| Kubernetes / Compute Resources / Namespace | 17118 | Per-namespace resources |
| Node Exporter Full | 1860 | Host-level metrics |
| Loki / Logs | 13639 | Log volume and search |
| Tempo / Service Graph | 16098 | Service dependency graph |
