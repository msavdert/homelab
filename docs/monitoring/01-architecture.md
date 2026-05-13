# Architecture

This document explains the signal flow, pipeline design decisions, and the role of each
component in the observability stack.

## Why OTel-Only?

The previous stack used Grafana Alloy as the collection agent. Alloy is excellent but
vendor-tied to the Grafana ecosystem. The new stack uses the OpenTelemetry Collector
exclusively, which means:

- **Vendor-agnostic wire protocol** — OTLP works with any backend
- **Single configuration model** — one YAML format for all signals
- **CNCF standard** — the industry is converging on OTel; skills transfer
- **ClickHouse exporter** — the OTel Collector contrib has a native `clickhouse` exporter;
  Alloy does not

The tradeoff: OTel Collector's `filelog` receiver requires more configuration than Alloy's
`loki.source.kubernetes` for pod log collection. The Agent config in this stack handles
that complexity explicitly.

## Signal Flow

### Metrics

```
kubeletstats receiver  ─┐
hostmetrics receiver   ─┤─► k8sattributes ─► resourcedetection ─► batch ─► Gateway
OTLP receiver (apps)   ─┘

Gateway:
  metrics pipeline         ─► prometheusremotewrite ─► VictoriaMetrics
  metrics/clickhouse pipeline ─► clickhouse exporter ─► ClickHouse otel_metrics_*
```

**kubeletstats** scrapes the kubelet's `/stats/summary` endpoint on each node. It produces
node, pod, container, and volume metrics. The Agent uses the node name from the Downward
API to target only the local kubelet — no cross-node scraping.

**hostmetrics** reads from `/hostfs` (the host root mounted into the Agent container).
It produces OS-level metrics: CPU, memory, disk I/O, filesystem, network, load average,
and process counts. This covers Talos-level metrics that kubeletstats doesn't expose.

**OTLP receiver** accepts metrics from instrumented applications and from Beyla. Beyla
sends RED metrics (request rate, error rate, duration) for all HTTP/gRPC/SQL services.

### Logs

```
filelog receiver ─┐
                  ├─► k8sattributes ─► resourcedetection ─► batch ─► Gateway
OTLP receiver    ─┘

Gateway:
  logs pipeline         ─► loki exporter ─► Loki
  logs/clickhouse pipeline ─► clickhouse exporter ─► ClickHouse otel_logs
```

**filelog** reads container log files from `/var/log/pods/*/*/*.log`. The CRI log format
(containerd/CRI-O) is parsed in a multi-step operator pipeline:

1. Parse the CRI header (`timestamp stream flags log`)
2. Extract pod metadata from the file path (`namespace_podname_uid/container/restart.log`)
3. Move the log content to the body
4. Attempt JSON parsing for structured logs
5. Set resource attributes from extracted path metadata
6. Clean up intermediate attributes

After the filelog operators run, `k8sattributes` enriches each log record with live
Kubernetes metadata (deployment name, labels, image tag) by querying the Kubernetes API.

### Traces

```
OTLP receiver (from apps + Beyla) ─► k8sattributes ─► tail_sampling ─► batch ─► Gateway

Gateway:
  traces pipeline         ─► otlp/tempo ─► Tempo
  traces/clickhouse pipeline ─► clickhouse exporter ─► ClickHouse otel_traces
```

Traces come from two sources:
- **Beyla** — eBPF-generated traces for HTTP/gRPC/SQL without code changes
- **Instrumented applications** — apps that use OTel SDKs send OTLP directly to the Agent

**Tail sampling** runs in the Gateway (not the Agent). This is critical for distributed
traces: a trace spans multiple services, so all spans for a trace must be collected before
a sampling decision can be made. The Agent forwards everything; the Gateway decides what
to keep.

## Component Roles

### OTel Agent (DaemonSet)

**Role:** Collect and forward. Do not process.

One pod per node. Responsibilities:
- Scrape node/pod/container metrics via kubeletstats
- Scrape OS metrics via hostmetrics
- Tail pod log files via filelog
- Receive OTLP from applications and Beyla on the same node
- Enrich all signals with Kubernetes metadata via k8sattributes
- Forward everything to the Gateway via OTLP/gRPC

The Agent applies only lightweight processing: `memory_limiter`, `k8sattributes`,
`resourcedetection`, and `batch`. No sampling, no routing decisions.

### OTel Gateway (Deployment + HPA)

**Role:** Process, sample, and fan out to multiple backends.

Horizontally scalable (HPA min:1, max:3). Responsibilities:
- Receive OTLP from all Agents and Beyla instances
- Apply tail sampling to traces (keep errors, slow spans, 10% of healthy traces)
- Apply a second pass of k8sattributes for Beyla-originated data
- Add cluster-level resource attributes (`k8s.cluster.name`, `deployment.environment`)
- Fork all signals to two destinations simultaneously:
  - LGTM stack (VictoriaMetrics, Loki, Tempo)
  - ClickHouse (analytics target)

### Grafana Beyla (DaemonSet)

**Role:** Zero-code eBPF instrumentation for all application pods.

One pod per node. Beyla attaches eBPF probes to running processes using Linux kernel
features (uprobes, kprobes, TC hooks). It intercepts HTTP/1.1, HTTP/2, gRPC, and SQL
calls at the kernel level — no code changes, no sidecar injection required.

Beyla produces:
- **RED metrics** — request rate, error rate, duration histograms per service/endpoint
- **Distributed traces** — spans with parent-child relationships for HTTP/gRPC calls

Beyla sends OTLP directly to the Gateway (not the Agent). This is intentional: Beyla
runs with `hostPID: true` and elevated capabilities, and its data is already enriched
with process-level metadata. The Gateway applies k8sattributes to add pod-level metadata.

### OTel Operator

**Role:** Manage `OpenTelemetryCollector` CRDs.

The Operator watches for `OpenTelemetryCollector` resources and creates the corresponding
Deployments, DaemonSets, Services, and ServiceAccounts. It handles rolling updates and
configuration reloads.

The `Instrumentation` CRD (auto-instrumentation via SDK injection) is **not used** in
this stack — Beyla handles instrumentation via eBPF instead.

## Forking Pipeline Design

The Gateway uses named pipelines to send the same data to multiple backends:

```yaml
service:
  pipelines:
    metrics:                  # → VictoriaMetrics
    metrics/clickhouse:       # → ClickHouse  (same receivers, different exporters)
    logs:                     # → Loki
    logs/clickhouse:          # → ClickHouse
    traces:                   # → Tempo
    traces/clickhouse:        # → ClickHouse
```

Each pipeline pair shares the same receivers but has independent processors and exporters.
This means:
- A ClickHouse outage does not affect the LGTM pipeline
- Each pipeline has its own retry queue and backpressure
- Batch sizes can be tuned independently per backend

The ClickHouse pipelines use a shorter `max_elapsed_time` for retry (120s vs 300s for LGTM)
because ClickHouse is the analytics target — data loss is acceptable, but indefinite
buffering is not.

## k8sattributes: The Most Important Processor

`k8sattributes` is what makes Kubernetes observability useful. Without it, you have metrics
and logs with no context about which pod, deployment, or namespace they came from.

The processor queries the Kubernetes API to add:

| Attribute | Example Value |
|-----------|--------------|
| `k8s.namespace.name` | `default` |
| `k8s.pod.name` | `checkout-7d9f8b-xk2p9` |
| `k8s.pod.uid` | `a1b2c3d4-...` |
| `k8s.deployment.name` | `checkout` |
| `k8s.node.name` | `worker-1` |
| `container.image.name` | `myregistry/checkout` |
| `container.image.tag` | `v1.2.3` |
| `app.kubernetes.io/name` | `checkout` |

The processor associates incoming data with a pod using multiple strategies (in order):
1. `k8s.pod.ip` resource attribute (set by apps that know their pod IP)
2. `k8s.pod.uid` resource attribute (set by filelog operators)
3. `k8s.pod.name` + `k8s.namespace.name` combination
4. Source IP of the connection (for OTLP data from apps)

## Tail Sampling Strategy

Tail sampling collects all spans for a trace before making a keep/drop decision.
The Gateway waits 10 seconds (`decision_wait`) for all spans to arrive, then applies:

| Policy | Condition | Action |
|--------|-----------|--------|
| `errors-policy` | `StatusCode = ERROR` | Always keep |
| `slow-traces-policy` | Duration > 1000ms | Always keep |
| `probabilistic-policy` | All other traces | Keep 10% |
| `critical-services-policy` | `k8s.namespace.name = kube-system` | Always keep |

This means:
- Every error trace is preserved for debugging
- Every slow trace is preserved for performance analysis
- 90% of healthy fast traces are dropped (reducing storage by ~10×)
- System-level traces are always kept

## Storage: local-path vs Longhorn

ClickHouse and VictoriaMetrics use `longhorn-db` StorageClass instead of standard replicated storage or generic `local-path`.

**Why longhorn-db?** 
In previous designs, `local-path` was used to avoid network I/O overhead. However, we now use a dedicated Longhorn StorageClass with the following parameters:
- `dataLocality: strict-local`: This ensures data stays on the same node as the Pod (Network overhead = 0), matching `local-path` performance.
- `numberOfReplicas: 1`: Minimizes write amplification while still being managed by a volume manager.

**The Advantage:**
Unlike `local-path`, using Longhorn with `strict-local` allows us to still benefit from:
1. **Volume Management:** Easy resizing and management via Kubernetes PVCs.
2. **Backups:** Native integration with S3/NFS for off-site backups.
3. **Snapshots:** Ability to take point-in-time snapshots before upgrades.

Loki and Tempo follow the same strategy where performance and manageability must be balanced.
