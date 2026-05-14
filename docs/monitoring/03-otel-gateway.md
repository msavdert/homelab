# OTel Gateway

The Gateway is the central processing unit of the pipeline. It receives all telemetry
from Agents and Beyla, applies tail sampling, enriches Beyla data with Kubernetes
metadata, and fans out to two backends simultaneously.

## Configuration File

`apps/base/observability/otel-gateway.yaml` — `OpenTelemetryCollector` CRD, mode: `deployment`.

## Scaling

```yaml
replicas: 1   # initial
# HPA: apps/base/observability/otel-gateway-hpa.yaml
# min: 1, max: 3
# scale up at 70% CPU or 75% memory
```

The Gateway scales horizontally. With 3 worker nodes each running an Agent and Beyla,
a single Gateway replica handles the load comfortably at homelab scale. The HPA kicks
in if a burst of traces or logs causes CPU/memory pressure.

**Important:** Tail sampling requires all spans of a trace to arrive at the same Gateway
replica. If you scale to multiple replicas, you must add a `loadbalancing` exporter in
the Agent to route spans by `traceID` to the same Gateway replica. At homelab scale
(single replica), this is not needed.

## Receivers

```yaml
otlp:
  protocols:
    grpc:
      endpoint: "0.0.0.0:4317"
    http:
      endpoint: "0.0.0.0:4318"
```

The Gateway accepts OTLP from:
- All OTel Agent pods (one per node)
- Beyla DaemonSet pods (one per node, sends directly to Gateway)

## Processors

### memory_limiter

```yaml
memory_limiter:
  check_interval: 1s
  limit_percentage: 80
  spike_limit_percentage: 25
```

The Gateway processes more data than the Agent (it receives from all nodes), so the
limit is set higher (80% vs 75% for the Agent). The container limit is 2Gi, so the
effective limit is ~1.6Gi.

### k8sattributes (second pass)

```yaml
k8sattributes:
  auth_type: serviceAccount
  extract:
    metadata: [k8s.pod.name, k8s.pod.uid, k8s.deployment.name, ...]
    labels:
      - tag_name: app.kubernetes.io/name
        key: app.kubernetes.io/name
        from: pod
  pod_association:
    - sources: [{from: resource_attribute, name: k8s.pod.ip}]
    - sources: [{from: resource_attribute, name: k8s.pod.uid}]
    - sources: [{from: connection}]
```

The Agent already runs k8sattributes for data it collects. The Gateway runs it again
for Beyla-originated data. Beyla sends OTLP directly to the Gateway (bypassing the
Agent), so its data may not have full Kubernetes metadata yet.

The Gateway's k8sattributes does **not** filter by node — it needs to look up pods
from all nodes because Beyla from any node can send to any Gateway replica.

### resource

```yaml
resource:
  attributes:
    - key: k8s.cluster.name
      value: "talos-homelab"
      action: upsert
    - key: deployment.environment
      value: "homelab"
      action: upsert
```

Adds cluster-level attributes to every signal. These are useful for multi-cluster
Grafana dashboards and for filtering in ClickHouse.

### tail_sampling

```yaml
tail_sampling:
  decision_wait: 10s
  num_traces: 50000
  expected_new_traces_per_sec: 100
  policies:
    - name: errors-policy
      type: status_code
      status_code:
        status_codes: [ERROR]
    - name: slow-traces-policy
      type: latency
      latency:
        threshold_ms: 1000
    - name: probabilistic-policy
      type: probabilistic
      probabilistic:
        sampling_percentage: 10
    - name: critical-services-policy
      type: string_attribute
      string_attribute:
        key: k8s.namespace.name
        values: [kube-system]
```

**How tail sampling works:**

1. The processor buffers all incoming spans in memory for `decision_wait` (10 seconds)
2. After 10 seconds, it evaluates all policies against the complete trace
3. If any policy matches, the trace is kept; otherwise it is dropped
4. `num_traces: 50000` is the maximum number of traces held in memory simultaneously

**Policy evaluation order:** Policies are evaluated in order. The first matching policy
wins. Error traces are checked first (most important), then slow traces, then
probabilistic sampling.

**Memory impact:** Each trace in memory consumes roughly 1-5 KB depending on span count.
50,000 traces × 5 KB = ~250 MB maximum. With the 2Gi container limit, this is safe.

**Why 10% probabilistic sampling?** At homelab scale, 10% of healthy traces is more than
enough for performance analysis. The important traces (errors, slow) are always kept.

### batch/lgtm and batch/clickhouse

```yaml
batch/lgtm:
  timeout: 10s
  send_batch_size: 2048
  send_batch_max_size: 4096

batch/clickhouse:
  timeout: 10s
  send_batch_size: 2048
  send_batch_max_size: 4096
```

Two separate batch processors — one per destination. This allows independent tuning.
Currently they have the same settings, but ClickHouse benefits from larger batches
(columnar writes are more efficient with more rows per insert).

## Exporters

### prometheusremotewrite/victoriametrics

```yaml
prometheusremotewrite/victoriametrics:
  endpoint: "http://victoriametrics.monitoring.svc.cluster.local:8428/api/v1/write"
  resource_to_telemetry_conversion:
    enabled: true
  external_labels:
    cluster: talos-homelab
```

`resource_to_telemetry_conversion: enabled: true` converts OTel resource attributes
(like `k8s.namespace.name`) into Prometheus labels. Without this, resource attributes
are dropped and you lose Kubernetes context in VictoriaMetrics.

### loki

```yaml
loki:
  endpoint: "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"
  labels:
    resource:
      k8s.namespace.name: "namespace"
      k8s.pod.name: "pod"
      k8s.container.name: "container"
      k8s.node.name: "node"
      k8s.deployment.name: "deployment"
      app.kubernetes.io/name: "app"
      k8s.cluster.name: "cluster"
```

Only the listed resource attributes become Loki stream labels. All other attributes
are stored as structured metadata. This is important — Loki's index is based on stream
labels, and high-cardinality labels (like pod name) cause index bloat.

The labels chosen here have bounded cardinality:
- `namespace` — tens of values
- `deployment` — hundreds of values
- `app` — hundreds of values
- `node` — single digits

`pod` is included despite higher cardinality because it is essential for debugging.

### otlp/tempo

```yaml
otlp/tempo:
  endpoint: "tempo.monitoring.svc.cluster.local:4317"
  tls:
    insecure: true
```

Sends traces to Tempo via OTLP/gRPC. Tempo is the trace storage backend for Grafana.

### clickhouse

```yaml
clickhouse:
  endpoint: "tcp://clickhouse.clickhouse.svc.cluster.local:9000"
  database: otel
  username: otel_writer
  password: "${env:CLICKHOUSE_OTEL_PASSWORD}"
  ttl: 72h
  create_schema: true
  logs_table_name: otel_logs
  traces_table_name: otel_traces
  metrics_table_name: otel_metrics
  timeout: 10s
  retry_on_failure:
    enabled: true
    max_elapsed_time: 120s   # shorter than LGTM — analytics target, data loss OK
  sending_queue:
    enabled: true
    queue_size: 1000
```

`create_schema: true` — the exporter creates the OTel tables automatically on first
connection. The `otel` database must exist (created by the `clickhouse-otel-init` Job).

`ttl: 72h` — all OTel tables have a 72-hour TTL. ClickHouse is the analytics/learning
target, not long-term storage.

`max_elapsed_time: 120s` — if ClickHouse is unavailable, the Gateway retries for 2
minutes then drops the data. This prevents the ClickHouse queue from growing indefinitely
and affecting the LGTM pipeline.

The password is injected from the `clickhouse-admin-credentials` Secret (synced from
1Password) via an environment variable.

## Forking Pipeline

```yaml
service:
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, k8sattributes, resource, batch/lgtm]
      exporters: [prometheusremotewrite/victoriametrics]

    metrics/clickhouse:
      receivers: [otlp]
      processors: [memory_limiter, k8sattributes, resource, batch/clickhouse]
      exporters: [clickhouse]

    logs:
      receivers: [otlp]
      processors: [memory_limiter, k8sattributes, resource, batch/lgtm]
      exporters: [loki]

    logs/clickhouse:
      receivers: [otlp]
      processors: [memory_limiter, k8sattributes, resource, batch/clickhouse]
      exporters: [clickhouse]

    traces:
      receivers: [otlp]
      processors: [memory_limiter, k8sattributes, resource, tail_sampling, batch/lgtm]
      exporters: [otlp/tempo]

    traces/clickhouse:
      receivers: [otlp]
      processors: [memory_limiter, k8sattributes, resource, tail_sampling, batch/clickhouse]
      exporters: [clickhouse]
```

Each signal type has two pipelines: one for LGTM, one for ClickHouse. They share the
same receivers (data enters once) but have independent processors and exporters.

The OTel Collector fan-out model: when multiple pipelines share a receiver, the receiver
sends data to all pipelines concurrently. A slow or failing exporter in one pipeline
does not block the other.

## HPA Configuration

`apps/base/observability/otel-gateway-hpa.yaml`:

```yaml
minReplicas: 1
maxReplicas: 3
metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 75
behavior:
  scaleUp:
    stabilizationWindowSeconds: 60    # wait 1 min before scaling up
  scaleDown:
    stabilizationWindowSeconds: 300   # wait 5 min before scaling down
```

Scale-down has a longer stabilization window to prevent flapping. Tail sampling buffers
traces in memory — scaling down too quickly would drop buffered traces.

## Resource Limits

```yaml
resources:
  requests:
    cpu: 256m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 2Gi
```

The Gateway is more resource-intensive than the Agent because it:
- Receives from all nodes (3× the data volume)
- Runs tail sampling (buffers up to 50k traces in memory)
- Runs two batch processors simultaneously
- Maintains retry queues for two backends
