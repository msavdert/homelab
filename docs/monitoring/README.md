# Kubernetes Monitoring & Observability with VictoriaMetrics

This directory contains the documentation and architectural details for the homelab's monitoring stack.

## Vision
To establish a professional, high-performance, and unified observability platform (Metrics, Logs, Traces) that follows industry best practices while maintaining low resource consumption.

## Core Technologies
- **Metrics**: [VictoriaMetrics](https://victoriametrics.com/) (Cluster mode for HA & Learning)
- **Logs**: [VictoriaLogs](https://docs.victoriametrics.com/victorialogs/)
- **Traces**: [VictoriaTraces](https://docs.victoriametrics.com/victoriatraces/)
- **Collection**: [OpenTelemetry](https://opentelemetry.io/) & [VMAgent](https://docs.victoriametrics.com/victoriametrics/vmagent/)
- **Visualization**: [Grafana](https://grafana.com/)
- **Infrastructure**: [Kubernetes](https://kubernetes.io/) (Talos Linux)
- **GitOps**: [ArgoCD](https://argoproj.github.io/cd/)
- **Storage**: [Longhorn](https://longhorn.io/)

## Architecture Overview
The monitoring stack is managed by the **VictoriaMetrics Operator**, which provides a cloud-native way to manage life cycles of various observability components.

### 1. Metrics Layer (VMCluster)
Instead of a single-binary approach, we use a modular cluster architecture:
- **vmstorage**: Persistent storage for metrics data.
- **vminsert**: Ingests data from agents and distributes it to storage nodes.
- **vmselect**: Fetches data from storage nodes for querying (Grafana/Alerts).

### 2. Logs Layer (VictoriaLogs)
Uses `VictoriaLogs` for high-efficiency log storage and retrieval, replacing heavier alternatives like Elasticsearch or Loki.

### 3. Traces Layer (VictoriaTraces)
Provides distributed tracing capabilities to visualize request flows and pinpoint latency bottlenecks.

### 4. Collection Layer (VMAgent & OTel)
- **VMAgent**: Efficiently scrapes Prometheus-style metrics from Kubernetes services.
- **OpenTelemetry Collector**: Standardizes the ingestion of traces and logs.

---

## Getting Started
1. Read the [VictoriaMetrics Ecosystem Guide](./ecosystem.md) to understand the component choices.
2. See [architecture.md](./architecture.md) for a technical deep dive.
3. Follow [deployment.md](./deployment.md) for step-by-step installation.
