# Grafana Beyla — eBPF Auto-Instrumentation

Beyla uses Linux eBPF to automatically instrument HTTP/1.1, HTTP/2, gRPC, and SQL
services without code changes or sidecar injection. It runs as a DaemonSet with
elevated privileges and sends OTLP directly to the OTel Gateway.

## Configuration File

`apps/base/observability/beyla.yaml` — DaemonSet + ConfigMap + RBAC.

## How Beyla Works

Beyla attaches eBPF programs to the Linux kernel at three levels:

1. **uprobes** — userspace probes attached to specific functions in running processes
   (e.g., Go's `net/http` handler, gRPC's `grpc.(*Server).handleStream`)
2. **kprobes** — kernel probes for system calls (e.g., `sys_read`, `sys_write`)
3. **TC hooks** — Traffic Control hooks on network interfaces for HTTP/2 and TLS traffic

This allows Beyla to intercept HTTP requests, gRPC calls, and SQL queries at the kernel
level — before TLS decryption, without modifying the application binary.

**What Beyla produces:**
- RED metrics (Rate, Errors, Duration) per service, endpoint, and HTTP method
- Distributed traces with parent-child span relationships
- Service graph metrics (which services call which)

## Talos OS Requirements

Talos has a strict security model. Running eBPF programs requires explicit configuration.

### 1. Apply the Talos Machine Config Patch

```bash
talosctl patch machineconfig \
  --patch @talos/beyla-ebpf-patch.yaml \
  --nodes <worker-1-ip>,<worker-2-ip>,<worker-3-ip>
```

The patch (`talos/beyla-ebpf-patch.yaml`) does three things:

**Kernel parameters (sysctls):**

| Parameter | Value | Reason |
|-----------|-------|--------|
| `net.core.bpf_jit_enable` | `1` | Enables BPF JIT compiler for performance |
| `kernel.perf_event_paranoia` | `1` | Allows `perf_event_open` for uprobes |
| `kernel.unprivileged_bpf_disabled` | `0` | Allows unprivileged BPF map creation |

**Kernel module:**
- `bpf` — ensures BTF (BPF Type Format) is available, required for CO-RE eBPF programs

**PSA exemption:**
```yaml
cluster:
  apiServer:
    admissionControl:
      - name: PodSecurity
        configuration:
          exemptions:
            namespaces:
              - observability
              - kube-system
```

Without this exemption, Kubernetes Pod Security Admission blocks Beyla's privileged pods
from starting in the `observability` namespace.

### 2. Wait for Node Reboot

After applying the patch, Talos reboots the nodes to apply kernel parameters. Wait for
all nodes to become healthy:

```bash
talosctl health --nodes <worker-1-ip>,<worker-2-ip>,<worker-3-ip>
```

## Security Context

Beyla requires elevated Linux capabilities to attach eBPF probes:

```yaml
securityContext:
  privileged: true
  runAsUser: 0
  capabilities:
    add:
      - CAP_BPF          # Load and run eBPF programs
      - CAP_SYS_ADMIN    # eBPF map operations, perf_event_open
      - CAP_NET_ADMIN    # TC (Traffic Control) hooks for network-level tracing
      - CAP_PERFMON      # perf_event_open for uprobes and kprobes
      - CAP_SYS_PTRACE   # Read /proc/<pid>/exe for process discovery
      - CAP_DAC_READ_SEARCH  # Read process memory maps
```

`privileged: true` is set as a belt-and-suspenders measure. On Talos, some eBPF
operations require capabilities that are only available in privileged mode.

`hostPID: true` is required for Beyla to see all processes on the host. Without it,
Beyla can only see processes in its own PID namespace and cannot attach probes to
application processes.

## Host Mounts

| Host Path | Mount Path | Purpose |
|-----------|-----------|---------|
| `/sys/kernel/debug` | `/sys/kernel/debug` | eBPF debugfs (required for some probe types) |
| `/proc` | `/proc` | Process discovery and memory map reading |

## Beyla Configuration (ConfigMap)

```yaml
discovery:
  instrument:
    - k8s_namespace: "^(?!kube-system|observability|kube-public|kube-node-lease).*"
```

Instruments all namespaces except system ones. The regex excludes:
- `kube-system` — Kubernetes system components (noisy, low value)
- `observability` — the monitoring stack itself (would create feedback loops)
- `kube-public`, `kube-node-lease` — Kubernetes internal namespaces

```yaml
routes:
  unmatched: heuristic
```

For URLs that don't match known patterns (e.g., `/api/v1/users/12345`), Beyla uses
heuristic grouping to reduce cardinality. Without this, every unique user ID would
create a separate metric series.

```yaml
attributes:
  kubernetes:
    enable: true
    cluster_name: talos-homelab
```

Decorates all metrics and traces with Kubernetes metadata (namespace, pod, deployment).

```yaml
otel_metrics_export:
  protocol: grpc
  features:
    - application          # HTTP/gRPC/SQL RED metrics
    - application_span     # Per-span metrics
    - application_service_graph  # Service-to-service call graph
    - application_process  # Process-level metrics

otel_traces_export:
  protocol: grpc
  sampler:
    name: parentbased_traceidratio
    arg: "0.1"   # 10% head sampling
```

Beyla applies 10% head sampling before sending to the Gateway. The Gateway then applies
tail sampling on top. This two-stage approach reduces the data volume sent over the
network while still allowing the Gateway to make intelligent keep/drop decisions on the
10% that arrives.

## OTLP Export Target

Beyla sends directly to the Gateway (not the Agent):

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-gateway-collector.observability.svc.cluster.local:4317"
  - name: OTEL_EXPORTER_OTLP_PROTOCOL
    value: grpc
```

The Gateway runs k8sattributes to enrich Beyla's data with pod metadata.

## Metrics Produced by Beyla

Beyla produces OpenTelemetry-standard HTTP and RPC metrics:

| Metric | Description |
|--------|-------------|
| `http.server.request.duration` | HTTP server request duration histogram |
| `http.server.active_requests` | Number of active HTTP server requests |
| `http.client.request.duration` | HTTP client request duration histogram |
| `rpc.server.duration` | gRPC server call duration histogram |
| `rpc.client.duration` | gRPC client call duration histogram |
| `db.client.operation.duration` | SQL query duration histogram |
| `process.cpu.time` | Process CPU time |
| `process.memory.usage` | Process memory usage |

All metrics include labels for `k8s.namespace.name`, `k8s.deployment.name`,
`k8s.pod.name`, `http.route`, `http.request.method`, `http.response.status_code`.

## Verifying Beyla is Working

```bash
# Check Beyla pods are running on all nodes
kubectl get pods -n observability -l app.kubernetes.io/name=beyla -o wide

# Check Beyla logs for instrumented processes
kubectl logs -n observability -l app.kubernetes.io/name=beyla --tail=50 | grep -i "instrument\|attach\|probe"

# Query VictoriaMetrics for Beyla metrics
kubectl port-forward -n monitoring svc/victoriametrics 8428:8428
# http://localhost:8428/vmui
# Query: http_server_request_duration_seconds_count
```

## Troubleshooting

**Beyla pods in Pending state:**
The `observability` namespace PSA exemption is missing. Apply `talos/beyla-ebpf-patch.yaml`
and reboot the nodes.

**Beyla pods running but no metrics:**
Check if the target processes are visible:
```bash
kubectl exec -n observability -it <beyla-pod> -- ls /proc | head -20
```
If `/proc` shows only a few PIDs, `hostPID: true` is not working — check the PSA exemption.

**eBPF program load failures:**
```bash
kubectl logs -n observability <beyla-pod> | grep -i "ebpf\|bpf\|permission"
```
Missing capabilities or kernel parameters. Verify the Talos patch was applied:
```bash
talosctl read /proc/sys/kernel/perf_event_paranoia --nodes <worker-ip>
# Should return: 1
```
