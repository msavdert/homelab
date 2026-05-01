# VictoriaMetrics K8s Stack: Unified Observability

This documentation details the implementation of the **VictoriaMetrics K8s Stack** (v0.76.0), providing a high-performance, resource-efficient alternative to the traditional Prometheus-Grafana stack.

---

## 1. Why VictoriaMetrics (VM)?

In a homelab environment where CPU, RAM, and Disk space are precious, VictoriaMetrics outshines the competition:
- **3x-6x Less Memory**: VM handles the same amount of metrics with a fraction of the RAM used by Prometheus.
- **10x Better Compression**: Data is stored much more efficiently, allowing for months of retention on small disks.
- **MetricsQL**: A super-set of PromQL that adds powerful functions (like `rate` over arbitrary intervals) and better performance for complex queries.
- **Native Long-Term Storage**: Unlike Prometheus, which requires sidecars like Thanos or Mimir for long-term storage, VM handles it natively out of the box.

---

## 2. Architecture & Components

We use the **`victoria-metrics-k8s-stack`**, which installs the following:
- **VMOperator**: The brain that manages the lifecycle of all other components.
- **VMSingle**: An all-in-one metrics database (Single Node). We chose this for the homelab as it avoids the networking/complexity overhead of a full `VMCluster`.
- **VMAgent**: A lightweight scraper that replaces the Prometheus scraper. It collects metrics and pushes them to VMSingle.
- **VMAlert**: Evaluates alerting rules and sends notifications to Alertmanager.
- **Grafana**: Pre-configured with official VictoriaMetrics dashboards.

---

## 3. Implementation Details (GitOps)

### Deployment Patterns:
- **Sync Wave (-4)**: Deployed after foundational networking (Cilium) and security (cert-manager) are ready.
- **ServerSideApply**: Used in ArgoCD to handle the large VictoriaMetrics CRDs without exceeding annotation limits.

### Homelab Optimizations:
- **Integer CPUs**: We set CPU limits to whole numbers (e.g., `1` instead of `500m`). VictoriaMetrics is written in Go and performs significantly better when it can map its threads to physical CPU cores.
- **Resource Parity**: Requests are set equal to Limits to prevent OOM (Out Of Memory) kills, which can corrupt the database during heavy ingestion.
- **Retention Strategy**: Configured for **6 months** by default. Thanks to VM's compression, this typically fits within a 20GB volume for a 4-node cluster.

---

## 4. Integration: CloudNativePG (CNPG)

One of the primary goals of this stack is monitoring our PostgreSQL databases.
- **Discovery**: The `VMAgent` automatically scans the cluster for `PodMonitor` resources.
- **Automation**: When `enablePodMonitor: true` is set in the CNPG cluster YAML, the operator creates a PodMonitor. `VMAgent` detects this via the `VMOperator` and starts scraping PostgreSQL metrics (port 9187) immediately.

---

## 5. Reference & Further Reading

- [VictoriaMetrics Official Documentation](https://docs.victoriametrics.com/)
- [Prometheus vs VictoriaMetrics: 2026 Comparison](https://victoriametrics.com/blog/victoriametrics-vs-prometheus/)
- [Monitoring Kubernetes with VictoriaMetrics Guide](https://docs.victoriametrics.com/guides/k8s-monitoring/)
- [MetricsQL Language Reference](https://docs.victoriametrics.com/metricsql/)

---
*Last Updated: 2026-05-01*
