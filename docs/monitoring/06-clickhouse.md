# ClickHouse

ClickHouse is the analytics and learning target. The OTel Gateway forks all telemetry
to ClickHouse in addition to the LGTM stack. It runs as a single node (no replication,
no Keeper) managed by the Altinity Kubernetes Operator.

## Configuration Files

- `apps/production/clickhouse-operator.yaml` — Altinity Operator (wave -5)
- `apps/production/clickhouse.yaml` — ArgoCD Application for the ClickHouse CR
- `apps/base/clickhouse/clickhouse-installation.yaml` — `ClickHouseInstallation` CR
- `apps/base/clickhouse/otel-db-init.yaml` — one-time init Job
- `apps/base/clickhouse/onepassword-items.yaml` — 1Password secret sync

## Altinity Operator

The Altinity Kubernetes Operator manages ClickHouse clusters via the
`ClickHouseInstallation` CRD. It handles:
- StatefulSet creation and lifecycle
- User and password management (reads from Kubernetes Secrets)
- Storage provisioning
- Rolling upgrades

**Version:** 0.26.3 (as of April 2026)
**Helm chart:** `altinity/altinity-clickhouse-operator`

## ClickHouseInstallation CR

```yaml
apiVersion: clickhouse.altinity.com/v1
kind: ClickHouseInstallation
metadata:
  name: clickhouse
  namespace: clickhouse
spec:
  configuration:
    clusters:
      - name: default
        layout:
          shardsCount: 1
          replicasCount: 1
```

Single shard, single replica. No Keeper required — Keeper is only needed for
replication between replicas.

### Users

```yaml
users:
  admin/k8s_secret_password: clickhouse/clickhouse-admin-credentials/password
  admin/networks/ip: "::/0"

  otel_writer/k8s_secret_password: clickhouse/clickhouse-admin-credentials/password
  otel_writer/networks/ip: "::/0"
```

The operator reads passwords from Kubernetes Secrets using the
`k8s_secret_password` syntax: `<namespace>/<secret-name>/<key>`.

Two users are created:
- `admin` — full access for management and ad-hoc queries
- `otel_writer` — used by the OTel Gateway's clickhouse exporter

Both users currently share the same password (from `clickhouse-admin-credentials`).
For stricter separation, create a separate 1Password item for `otel_writer`.

### Storage

```yaml
volumeClaimTemplates:
  - name: clickhouse-data
    spec:
      storageClassName: local-path
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 50Gi
```

`local-path` provides direct disk access without network overhead. ClickHouse is
write-heavy (continuous OTel data ingestion) and benefits significantly from local I/O.

**Note:** local-path creates node affinity. If the node running ClickHouse fails,
the pod cannot be rescheduled until the node recovers. For a learning/analytics target,
this is acceptable.

### ClickHouse Settings

```yaml
settings:
  max_memory_usage: 10000000000          # 10 GB per query
  max_memory_usage_for_all_queries: 12000000000  # 12 GB total
  allow_experimental_object_type: 1      # enables JSON type (beta)
  logger/level: warning
```

## OTel Database Schema

The OTel Gateway's `clickhouse` exporter creates the following tables in the `otel`
database with `create_schema: true`:

### otel_logs

```sql
CREATE TABLE otel.otel_logs (
    Timestamp           DateTime64(9),
    TraceId             String,
    SpanId              String,
    TraceFlags          UInt32,
    SeverityText        LowCardinality(String),
    SeverityNumber      Int32,
    ServiceName         LowCardinality(String),
    Body                String,
    ResourceSchemaUrl   String,
    ResourceAttributes  Map(LowCardinality(String), String),
    ScopeSchemaUrl      String,
    ScopeName           String,
    ScopeVersion        String,
    ScopeAttributes     Map(LowCardinality(String), String),
    LogAttributes       Map(LowCardinality(String), String),
    INDEX idx_trace_id  TraceId TYPE bloom_filter(0.001) GRANULARITY 1,
    INDEX idx_body      Body TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 1
)
ENGINE = MergeTree
PARTITION BY toDate(Timestamp)
ORDER BY (toStartOfFiveMinutes(Timestamp), ServiceName, Timestamp)
TTL toDateTime(Timestamp) + INTERVAL 72 HOUR
```

### otel_traces

```sql
CREATE TABLE otel.otel_traces (
    Timestamp           DateTime64(9),
    TraceId             String,
    SpanId              String,
    ParentSpanId        String,
    SpanName            LowCardinality(String),
    SpanKind            LowCardinality(String),
    ServiceName         LowCardinality(String),
    ResourceAttributes  Map(LowCardinality(String), String),
    SpanAttributes      Map(LowCardinality(String), String),
    Duration            Int64,
    StatusCode          LowCardinality(String),
    StatusMessage       String,
    ...
)
ENGINE = MergeTree
PARTITION BY toDate(Timestamp)
ORDER BY (toStartOfHour(Timestamp), ServiceName, SpanName, toUnixTimestamp(Timestamp), TraceId)
TTL toDateTime(Timestamp) + INTERVAL 72 HOUR
```

### otel_metrics_* (multiple tables)

Metrics are split by type:

| Table | Metric Type | Use Case |
|-------|-------------|---------|
| `otel_metrics_gauge` | Gauge | Current values (CPU %, memory) |
| `otel_metrics_sum` | Sum/Counter | Cumulative counts (requests total) |
| `otel_metrics_histogram` | Histogram | Distributions (latency buckets) |
| `otel_metrics_exp_histogram` | Exponential Histogram | High-resolution distributions |
| `otel_metrics_summary` | Summary | Pre-computed percentiles |

All metric tables have a 72-hour TTL.

## Useful SQL Queries

### Connect to ClickHouse

```bash
# Get the pod name
CH_POD=$(kubectl get pod -n clickhouse \
  -l clickhouse.altinity.com/chi=clickhouse \
  -o jsonpath='{.items[0].metadata.name}')

# Connect interactively
kubectl exec -n clickhouse -it $CH_POD -- \
  clickhouse-client --user admin --password "$CH_PASS"

# Run a single query
kubectl exec -n clickhouse $CH_POD -- \
  clickhouse-client --user admin --password "$CH_PASS" \
  --query "SELECT count() FROM otel.otel_logs"
```

### Log Queries

```sql
-- Recent error logs
SELECT Timestamp, ServiceName, SeverityText, Body
FROM otel.otel_logs
WHERE SeverityText IN ('ERROR', 'FATAL')
  AND Timestamp >= now() - INTERVAL 1 HOUR
ORDER BY Timestamp DESC
LIMIT 100;

-- Log volume by service (last hour)
SELECT ServiceName, count() AS log_count
FROM otel.otel_logs
WHERE Timestamp >= now() - INTERVAL 1 HOUR
GROUP BY ServiceName
ORDER BY log_count DESC;

-- Full-text search (uses bloom filter index)
SELECT Timestamp, ServiceName, Body
FROM otel.otel_logs
WHERE hasToken(Body, 'timeout')
  AND Timestamp >= now() - INTERVAL 1 HOUR
LIMIT 50;

-- Logs from a specific namespace
SELECT Timestamp, Body
FROM otel.otel_logs
WHERE ResourceAttributes['k8s.namespace.name'] = 'default'
  AND Timestamp >= now() - INTERVAL 1 HOUR
ORDER BY Timestamp DESC
LIMIT 100;
```

### Trace Queries

```sql
-- Slow spans (> 500ms)
SELECT TraceId, SpanName, ServiceName,
       Duration / 1e6 AS duration_ms
FROM otel.otel_traces
WHERE Duration > 500000000   -- nanoseconds
  AND Timestamp >= now() - INTERVAL 1 HOUR
ORDER BY Duration DESC
LIMIT 50;

-- Error spans
SELECT TraceId, SpanName, ServiceName, StatusMessage
FROM otel.otel_traces
WHERE StatusCode = 'Error'
  AND Timestamp >= now() - INTERVAL 1 HOUR
ORDER BY Timestamp DESC
LIMIT 100;

-- Service call graph (which services call which)
SELECT
    ResourceAttributes['k8s.deployment.name'] AS caller,
    SpanAttributes['peer.service'] AS callee,
    count() AS call_count,
    avg(Duration / 1e6) AS avg_duration_ms
FROM otel.otel_traces
WHERE SpanKind = 'Client'
  AND Timestamp >= now() - INTERVAL 1 HOUR
GROUP BY caller, callee
ORDER BY call_count DESC;
```

### Metric Queries

```sql
-- HTTP request rate by service (last 5 minutes)
SELECT
    ServiceName,
    MetricName,
    sum(Value) AS total_requests
FROM otel.otel_metrics_sum
WHERE MetricName = 'http.server.request.duration'
  AND TimeUnix >= now() - INTERVAL 5 MINUTE
GROUP BY ServiceName, MetricName
ORDER BY total_requests DESC;

-- Node CPU utilization
SELECT
    ResourceAttributes['k8s.node.name'] AS node,
    Attributes['state'] AS cpu_state,
    avg(Value) AS avg_utilization
FROM otel.otel_metrics_gauge
WHERE MetricName = 'system.cpu.utilization'
  AND TimeUnix >= now() - INTERVAL 5 MINUTE
GROUP BY node, cpu_state
ORDER BY node, cpu_state;

-- Pod memory working set
SELECT
    ResourceAttributes['k8s.pod.name'] AS pod,
    ResourceAttributes['k8s.namespace.name'] AS namespace,
    max(Value) / 1024 / 1024 AS max_memory_mb
FROM otel.otel_metrics_gauge
WHERE MetricName = 'k8s.pod.memory.working_set'
  AND TimeUnix >= now() - INTERVAL 5 MINUTE
GROUP BY pod, namespace
ORDER BY max_memory_mb DESC
LIMIT 20;
```

## OTel Database Init Job

`apps/base/clickhouse/otel-db-init.yaml` runs as an ArgoCD sync hook (wave -2):

```yaml
annotations:
  argocd.argoproj.io/hook: Sync
  argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
```

The Job:
1. Waits for ClickHouse to be ready (polls `/SELECT 1`)
2. Creates the `otel` database
3. Grants `otel_writer` full access to `otel.*`

The OTel Gateway's `create_schema: true` then creates the individual tables on first
connection.

## TTL and Data Retention

All OTel tables have a 72-hour TTL:

```sql
TTL toDateTime(Timestamp) + INTERVAL 72 HOUR
```

ClickHouse runs TTL cleanup asynchronously via the MergeTree background merge process.
Data is not deleted immediately at 72 hours — it is deleted during the next merge
operation after the TTL expires.

To check how much data is stored:

```sql
SELECT
    table,
    formatReadableSize(sum(bytes_on_disk)) AS size_on_disk,
    sum(rows) AS total_rows,
    min(min_time) AS oldest_data,
    max(max_time) AS newest_data
FROM system.parts
WHERE database = 'otel' AND active = 1
GROUP BY table
ORDER BY sum(bytes_on_disk) DESC;
```

## Accessing ClickHouse HTTP Interface

ClickHouse exposes an HTTP interface on port 8123 for SQL queries via curl or the
ClickHouse HTTP client:

```bash
kubectl port-forward -n clickhouse svc/clickhouse-clickhouse 8123:8123

# Run a query via HTTP
curl "http://localhost:8123/?user=admin&password=$CH_PASS" \
  --data "SELECT count() FROM otel.otel_logs"
```
