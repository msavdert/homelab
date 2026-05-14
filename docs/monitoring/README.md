# Observability Stack

OTel-native, dual-target observability stack for a Talos Kubernetes homelab.
All telemetry flows exclusively through OpenTelemetry — no Alloy, no Promtail, no Fluentd.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster (Talos v1.7+)                  │
│                    3 worker nodes × 4 CPU / 16 GB RAM               │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │           Grafana Beyla (DaemonSet) — eBPF                   │  │
│  │   Zero-code HTTP/gRPC/SQL instrumentation                    │  │
│  │   Produces RED metrics + distributed traces                  │  │
│  └──────────────────────────┬───────────────────────────────────┘  │
│                             │ OTLP/gRPC                             │
│  ┌──────────────────────────▼───────────────────────────────────┐  │
│  │           OTel Agent (DaemonSet)                              │  │
│  │   kubeletstats · hostmetrics · filelog · OTLP receiver        │  │
│  │   k8sattributes enrichment — dumb forwarder to Gateway        │  │
│  └──────────────────────────┬───────────────────────────────────┘  │
│                             │ OTLP/gRPC                             │
│  ┌──────────────────────────▼───────────────────────────────────┐  │
│  │           OTel Gateway (Deployment, HPA min:1 max:3)          │  │
│  │   tail_sampling · batching · memory_limiter                   │  │
│  │                  FORKING PIPELINE                             │  │
│  └──────┬──────────────────────────────────────┬────────────────┘  │
│         │                                      │                   │
│         ▼  LGTM target (production)            ▼  ClickHouse target│
│  ┌─────────────────────┐          ┌──────────────────────────────┐ │
│  │  namespace:         │          │  namespace: clickhouse        │ │
│  │  monitoring         │          │                              │ │
│  │                     │          │  ClickHouse (single node)    │ │
│  │  VictoriaMetrics    │          │  otel_logs                   │ │
│  │  Loki               │          │  otel_traces                 │ │
│  │  Tempo              │          │  otel_metrics_*              │ │
│  │  Grafana            │          │                              │ │
│  └─────────────────────┘          │  (analytics / learning)      │ │
│                                   └──────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

## Design Principles

**Everything through OpenTelemetry.** Metrics, logs, and traces all use OTLP as the wire
protocol. No vendor-specific agents. The pipeline is backend-agnostic — swap VictoriaMetrics
for Prometheus or Loki for Elasticsearch without touching the Agent or Beyla.

**Agent is a dumb forwarder.** The OTel Agent collects and forwards. All processing
(batching, tail-sampling, enrichment of Beyla data) happens in the Gateway. This keeps
Agent resource usage low and makes the Gateway independently scalable.

**Dual-target forking.** The Gateway sends the same telemetry to two destinations
simultaneously using separate named pipelines (`metrics`, `metrics/clickhouse`, etc.).
LGTM is the production observability system. ClickHouse is the analytics and learning target.

**Zero-code instrumentation via eBPF.** Beyla attaches eBPF probes to running processes
without requiring code changes or sidecar injection. It produces RED metrics and traces
for all HTTP/gRPC/SQL services automatically.

## Namespace Strategy

| Namespace | Contents | Notes |
|-----------|----------|-------|
| `observability` | OTel Operator, OTel Agent, OTel Gateway, Beyla | Privileged PSA |
| `monitoring` | VictoriaMetrics, Loki, Tempo, Grafana | Standard PSA |
| `clickhouse` | Altinity Operator, ClickHouse | Privileged PSA |

## Component Versions

| Component | Helm Chart / Image | Version |
|-----------|-------------------|---------|
| OTel Operator | opentelemetry-helm/opentelemetry-operator | 0.78.0 |
| OTel Agent / Gateway | `opentelemetry.io/v1beta1` CRD | managed by operator |
| Grafana Beyla | `grafana/beyla` (DaemonSet image) | 1.9.0 |
| **Grafana Operator** | `oci://ghcr.io/grafana/helm-charts/grafana-operator` | **v5.22.2** |
| **Grafana** | `Grafana` CR (managed by operator) | via operator |
| VictoriaMetrics | victoriametrics/victoria-metrics-single | 0.37.0 |
| Loki | grafana-community/loki (standalone chart) | 13.5.0 |
| **Tempo Operator** | grafana/tempo-operator | **0.20.0** |
| **Tempo** | `TempoMonolithic` CR (managed by operator) | Tempo v2.10.0 |
| Altinity Operator | altinity/altinity-clickhouse-operator | 0.26.3 |
| ClickHouse | `clickhouse/clickhouse-server` image | 25.3-lts |

## ArgoCD Sync Wave Order

| Wave | Applications | Reason |
|------|-------------|--------|
| `-10` | cilium, longhorn, gateway-api-crds | Core infrastructure |
| `-8` | cert-manager, onepassword | TLS and secret management |
| `-5` | clickhouse-operator, grafana-operator, tempo-operator, observability-operator | CRDs and operators before CRs |
| `-4` | victoriametrics, loki, tempo | Storage backends before writers |
| `-3` | clickhouse, grafana, observability | Applications and CRs |

## Documentation Index

| Document | Contents |
|----------|----------|
| [01-architecture.md](01-architecture.md) | Signal flow, pipeline design, component roles |
| [02-otel-agent.md](02-otel-agent.md) | Agent config: filelog, kubeletstats, k8sattributes |
| [03-otel-gateway.md](03-otel-gateway.md) | Gateway config: tail sampling, forking pipeline |
| [04-beyla.md](04-beyla.md) | Beyla eBPF: Talos setup, capabilities, config |
| [05-lgtm-stack.md](05-lgtm-stack.md) | VictoriaMetrics, Loki, Tempo, Grafana |
| [06-clickhouse.md](06-clickhouse.md) | ClickHouse single node, OTel schema, queries |
| [07-installation.md](07-installation.md) | Step-by-step deployment guide |
| [08-troubleshooting.md](08-troubleshooting.md) | Common issues and debugging commands |

## Quick Reference

```bash
# Check all observability pods
kubectl get pods -n observability
kubectl get pods -n monitoring
kubectl get pods -n clickhouse

# Verify Agent is running on every node (should equal node count)
kubectl get pods -n observability -l app.kubernetes.io/name=otel-agent-collector

# Verify Gateway HPA
kubectl get hpa -n observability

# Check Gateway logs for pipeline errors
kubectl logs -n observability -l app.kubernetes.io/name=otel-gateway-collector --tail=50

# Access Grafana (via Cloudflare Tunnel)
# https://grafana.savdert.com

# Port-forward VictoriaMetrics UI
kubectl port-forward -n monitoring svc/victoriametrics 8428:8428
# http://localhost:8428/vmui

# Query ClickHouse directly
kubectl exec -n clickhouse -it \
  $(kubectl get pod -n clickhouse -l clickhouse.altinity.com/chi=clickhouse \
    -o jsonpath='{.items[0].metadata.name}') \
  -- clickhouse-client --user admin --password "$CH_PASS"
```

## Access URLs

| Service | URL | Auth |
|---------|-----|------|
| Grafana | https://grafana.savdert.com | 1Password: grafana-admin-credentials |
| VictoriaMetrics UI | https://victoriametrics.savdert.com | none (internal) |
| ClickHouse HTTP | cluster-internal only | 1Password: clickhouse-admin-credentials |
