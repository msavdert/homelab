# SigNoz K8s Infrastructure Monitoring

This component is responsible for collecting telemetry data from the Kubernetes cluster itself and forwarding it to the SigNoz backend.

## 🚀 Overview

The `k8s-infra` chart deploys OpenTelemetry agents as a **DaemonSet** on every node and a **Deployment** for cluster-level metrics. It replaces the need for separate Prometheus exporters and log collectors.

## 🛠 Configuration

- **Backend Endpoint**: Configured to point to the SigNoz OTEL Collector in the same cluster.
- **Presets Enabled**:
    - `logsCollection`: Collects stdout/stderr logs from all containers.
    - `hostMetrics`: Collects CPU, RAM, Disk, and Network metrics from the nodes.
    - `kubeletStats`: Collects container-level resource usage.
    - `kubernetesEvents`: Tracks cluster events (pod starts, crashes, etc.).
    - `clusterMetrics`: Cluster-wide metrics (via API server).

## 📊 Usage

Once deployed, the metrics and logs will automatically appear in the SigNoz UI under:
- **Dashboards**: Official SigNoz dashboards for K8s Infrastructure.
- **Logs**: Real-time log searching for any pod in the cluster.
- **Service Graph**: Infrastructure-level connectivity visualization.

## 📚 Resources

- [SigNoz K8s-Infra Docs](https://signoz.io/docs/userguide/kubernetes-infra/)
- [OpenTelemetry Collector K8s Operator](https://github.com/open-telemetry/opentelemetry-operator)
