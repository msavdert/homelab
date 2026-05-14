# VictoriaMetrics Operator

The "brain" of the monitoring stack, managing VictoriaMetrics components and converting Prometheus CRDs.

## 1. Overview
The VM Operator simplifies the management of VictoriaMetrics components (VMSingle, VMAgent, VMAlert) and provides seamless migration from Prometheus-based stacks.

## 2. Installation Details
- **Method:** ArgoCD / Kustomize (Helm Inflation).
- **Source:** [victoriametrics.github.io/helm-charts](https://victoriametrics.github.io/helm-charts)
- **Version:** `v0.69.0` (Chart `0.62.1`)
- **Sync Wave:** `6`

## 3. Configuration Rationale
- **Prometheus Converter:** Enabled. This allows the operator to automatically discover and convert standard `ServiceMonitor`, `PodMonitor`, and `PrometheusRule` resources into VictoriaMetrics configuration.
- **ArgoCD Compatibility:** `ServerSideApply` is enabled to handle the extensive CRDs without hitting metadata limits.
- **Admission Webhooks:** Disabled for simplicity (homelab environment).

## 4. References
- [Operator Documentation](https://docs.victoriametrics.com/operator/)
- [ArgoCD & VM Operator Guide](https://docs.victoriametrics.com/helm/victoria-metrics-operator/#argocd-issues)
