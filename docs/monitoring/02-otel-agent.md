# OTel Agent

The OTel Agent is a DaemonSet that runs one pod per node. Its only job is to collect
telemetry from the local node and forward it to the Gateway. It does not sample, route,
or make any backend decisions.

## Configuration File

`apps/base/observability/otel-agent.yaml` — `OpenTelemetryCollector` CRD, mode: `daemonset`.

## Components

- **OTel Collector (DaemonSet):** The core agent collecting and forwarding signals.
- **Target Allocator:** A sidecar/deployment that discovers scrape targets from `ServiceMonitor` and `PodMonitor` CRDs.

### kubeletstats

Scrapes the kubelet's `/stats/summary` endpoint to collect node, pod, container, and
volume metrics.

```yaml
kubeletstats:
  collection_interval: 30s
  auth_type: serviceAccount
  endpoint: "https://${env:K8S_NODE_NAME}:10250"
  insecure_skip_verify: true
  metric_groups: [node, pod, container, volume]
  extra_metadata_labels:
    - container.id
    - k8s.volume.type
  k8s_api_config:
    auth_type: serviceAccount
```

Key points:
- `endpoint` uses `K8S_NODE_NAME` from the Downward API — each Agent pod targets only
  its own node's kubelet, preventing duplicate metrics
- `insecure_skip_verify: true` is required because the kubelet uses a self-signed cert
- `k8s_api_config` enables the processor to enrich metrics with pod labels from the API

**Metrics produced (sample):**

| Metric | Description |
|--------|-------------|
| `k8s.node.cpu.usage` | Node CPU usage in nanoseconds |
| `k8s.node.memory.working_set` | Node memory working set |
| `k8s.pod.cpu.usage` | Pod CPU usage |
| `k8s.pod.memory.working_set` | Pod memory working set |
| `k8s.container.cpu.usage` | Container CPU usage |
| `k8s.container.memory.working_set` | Container memory working set |
| `k8s.volume.capacity` | Volume capacity |

### hostmetrics

Reads OS-level metrics from `/hostfs` (the host root filesystem mounted read-only).

```yaml
hostmetrics:
  collection_interval: 30s
  root_path: /hostfs
  scrapers:
    cpu:
      metrics:
        system.cpu.utilization:
          enabled: true
    memory:
      metrics:
        system.memory.utilization:
          enabled: true
    disk: {}
    filesystem:
      exclude_mount_points: ...   # excludes /dev/*, /proc/*, /sys/*, overlay, etc.
      exclude_fs_types: ...       # excludes tmpfs, cgroup2, debugfs, etc.
    load: {}
    network: {}
    paging: {}
    processes: {}
```

The filesystem scraper excludes virtual and container-internal mount points to avoid
noise. Only real disk mounts (e.g., `/`, `/var`, `/data`) are reported.

**Metrics produced (sample):**

| Metric | Description |
|--------|-------------|
| `system.cpu.utilization` | CPU utilization ratio per state (user, system, idle) |
| `system.memory.utilization` | Memory utilization ratio |
| `system.disk.io` | Disk read/write bytes |
| `system.filesystem.utilization` | Filesystem usage ratio |
| `system.network.io` | Network bytes sent/received |
| `system.load_average.1m` | 1-minute load average |
| `system.processes.count` | Number of processes by state |

### filelog

Reads container log files from `/var/log/pods/*/*/*.log` on the host.

```yaml
filelog:
  include:
    - /var/log/pods/*/*/*.log
  exclude:
    - /var/log/pods/observability_otel-agent*/*/*.log
  start_at: end
  include_file_path: true
  include_file_name: false
  operators: [...]
```

`start_at: end` means the Agent only reads new log lines after startup — it does not
replay historical logs. This prevents log storms when the Agent restarts.

The Agent's own logs are excluded to prevent a feedback loop.

#### Log Parsing Pipeline (operators)

The CRI log format used by containerd and CRI-O looks like:

```
2024-01-15T10:30:00.000000000Z stdout F {"level":"info","msg":"server started","port":8080}
```

The operator pipeline processes this in 6 steps:

**Step 1 — Parse CRI header:**
```
regex: '^(?P<time>[^ Z]+) (?P<stream>stdout|stderr) (?P<logtag>[^ ]*) ?(?P<log>.*)$'
```
Extracts `time`, `stream` (stdout/stderr), `logtag` (F=full, P=partial), and `log` (body).

**Step 2 — Extract metadata from file path:**
```
regex: '^.*\/(?P<namespace>[^_]+)_(?P<pod_name>[^_]+)_(?P<uid>[a-f0-9\-]+)\/(?P<container_name>[^\/_]+)\/(?P<restart_count>\d+)\.log$'
```
The file path `/var/log/pods/default_checkout-7d9f8b-xk2p9_a1b2c3/checkout/0.log`
yields: `namespace=default`, `pod_name=checkout-7d9f8b-xk2p9`, `uid=a1b2c3`,
`container_name=checkout`, `restart_count=0`.

**Step 3 — Move log content to body:**
Moves `attributes.log` → `body`.

**Step 4 — Parse JSON body (if applicable):**
```yaml
- type: json_parser
  if: 'body matches "^\\{"'
```
If the log line is JSON (most structured loggers emit JSON), parse it. The parsed fields
become attributes. If parsing fails, the raw string body is kept.

**Step 5 — Set resource attributes:**
```yaml
- type: add
  field: resource["k8s.namespace.name"]
  value: EXPR(attributes.namespace)
```
Promotes the extracted path metadata to resource attributes. Resource attributes are
indexed by backends (Loki uses them as stream labels, ClickHouse stores them in
`ResourceAttributes`).

**Step 6 — Clean up:**
Removes intermediate attributes (`namespace`, `pod_name`, `uid`, `container_name`,
`restart_count`, `time`, `stream`, `logtag`) that were only needed for parsing.

### prometheus

The prometheus receiver is dynamically configured by the Target Allocator to scrape 
targets defined via `ServiceMonitor` and `PodMonitor` CRDs.

```yaml
prometheus:
  config:
    scrape_configs:
      - job_name: 'otel-collector'
        scrape_interval: 20s
        static_configs:
          - targets: ['0.0.0.0:8888']
  target_allocator:
    endpoint: http://otel-agent-targetallocator:80
    interval: 30s
    collector_id: ${env:K8S_NODE_NAME}
```

This setup enables:
- **Zero-touch discovery:** Add a `ServiceMonitor`, and OTel starts scraping it.
- **Kube-State-Metrics integration:** Automatically scrapes KSM via its ServiceMonitor.
- **Shard-aware scraping:** The Target Allocator ensures targets are distributed across 
  all Agent pods.

### OTLP Receiver

Accepts OTLP from applications and Beyla running on the same node.

```yaml
otlp:
  protocols:
    grpc:
      endpoint: "0.0.0.0:4317"
    http:
      endpoint: "0.0.0.0:4318"
```

Applications configure their OTel SDK with:
```
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-agent-collector.observability.svc.cluster.local:4317
```

## Processors

### k8sattributes

The most important processor. Queries the Kubernetes API to enrich every metric, log,
and trace with pod metadata.

```yaml
k8sattributes:
  auth_type: serviceAccount
  filter:
    node_from_env_var: K8S_NODE_NAME   # only process pods on this node
  extract:
    metadata:
      - k8s.pod.name
      - k8s.pod.uid
      - k8s.deployment.name
      - k8s.statefulset.name
      - k8s.daemonset.name
      - k8s.namespace.name
      - k8s.node.name
      - container.image.name
      - container.image.tag
    labels:
      - tag_name: app.kubernetes.io/name
        key: app.kubernetes.io/name
        from: pod
  pod_association:
    - sources: [{from: resource_attribute, name: k8s.pod.ip}]
    - sources: [{from: resource_attribute, name: k8s.pod.uid}]
    - sources: [{from: resource_attribute, name: k8s.pod.name},
                {from: resource_attribute, name: k8s.namespace.name}]
    - sources: [{from: connection}]
```

`filter.node_from_env_var` restricts the processor to only look up pods on the current
node. Without this, every Agent pod would query the API for all pods in the cluster,
creating unnecessary load.

`pod_association` defines how to match incoming telemetry to a pod. The processor tries
each strategy in order until one succeeds:
1. `k8s.pod.ip` — set by filelog operators and some apps
2. `k8s.pod.uid` — set by filelog operators
3. `k8s.pod.name` + `k8s.namespace.name` — set by filelog operators
4. Source IP of the TCP connection — works for OTLP from apps

### resourcedetection

Adds node and OS metadata that is not available from Kubernetes:

```yaml
resourcedetection:
  detectors: [env, k8snode, system]
```

- `env` — reads `OTEL_RESOURCE_ATTRIBUTES` env var (useful for manual overrides)
- `k8snode` — adds `k8s.node.name` and `k8s.node.uid`
- `system` — adds `host.name`, `os.type`, `os.description`

### memory_limiter

Prevents the Agent from consuming too much memory and being OOM-killed:

```yaml
memory_limiter:
  check_interval: 1s
  limit_percentage: 75
  spike_limit_percentage: 20
```

When memory usage exceeds 75% of the container limit, the processor starts dropping data
and returning errors to receivers. This is preferable to an OOM kill, which would cause
a gap in collection.

### batch

Groups data into batches before sending to the Gateway:

```yaml
batch:
  timeout: 5s
  send_batch_size: 512
  send_batch_max_size: 1024
```

Small batches (512 items, 5s timeout) keep latency low. The Agent is a forwarder — it
should not buffer data for long.

## Pipelines

```yaml
pipelines:
  metrics:
    receivers: [kubeletstats, hostmetrics, prometheus, otlp]
    processors: [memory_limiter, k8sattributes, resourcedetection, batch]
    exporters: [otlp/gateway]

  logs:
    receivers: [filelog, otlp]
    processors: [memory_limiter, k8sattributes, resourcedetection, batch]
    exporters: [otlp/gateway]

  traces:
    receivers: [otlp]
    processors: [memory_limiter, k8sattributes, resourcedetection, batch]
    exporters: [otlp/gateway]
```

All three pipelines export to a single destination: the Gateway.

## RBAC Requirements

The Agent ServiceAccount needs cluster-wide read access:

| Resource | Verbs | Reason |
|----------|-------|--------|
| pods, namespaces, nodes, services, endpoints | get, list, watch | k8sattributes lookup & Target Allocator discovery |
| endpointslices | get, list, watch | Target Allocator discovery (modern API) |
| nodes/stats, nodes/proxy, nodes/metrics | get | kubeletstats & prometheus scraping |
| replicasets, deployments, statefulsets, daemonsets | get, list, watch | deployment name resolution |
| servicemonitors, podmonitors | get, list, watch | Target Allocator CRD discovery |

## Host Mounts

| Host Path | Mount Path | Purpose |
|-----------|-----------|---------|
| `/var/log/pods` | `/var/log/pods` | filelog log collection |
| `/var/lib/docker/containers` | `/var/lib/docker/containers` | container metadata |
| `/` | `/hostfs` | hostmetrics OS metrics |

All mounts are read-only. The Agent runs as root (`runAsUser: 0`) to read log files
owned by the container runtime.

## Downward API Environment Variables

| Variable | Value | Used By |
|----------|-------|---------|
| `K8S_NODE_NAME` | `spec.nodeName` | kubeletstats endpoint, k8sattributes filter |
| `K8S_POD_NAME` | `metadata.name` | self-identification |
| `K8S_POD_NAMESPACE` | `metadata.namespace` | self-identification |
| `K8S_POD_IP` | `status.podIP` | self-identification |
