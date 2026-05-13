# Prometheus Operator CRDs

Standard Custom Resource Definitions for the Prometheus ecosystem, required by VictoriaMetrics and OpenTelemetry.

## 1. Overview
This component provides the essential Kubernetes API extensions (`ServiceMonitor`, `PodMonitor`, `PrometheusRule`, etc.) without deploying the full Prometheus stack. 

## 2. Rationale
The VictoriaMetrics Operator's **Prometheus Converter** requires these CRDs to be present in the cluster to watch and convert them into VictoriaMetrics resources. Without these, the `vm-operator` would fail to synchronize its caches.

## 3. Installation Details
- **Method:** ArgoCD / Kustomize (Helm Inflation).
- **Source:** [prometheus-community.github.io/helm-charts](https://prometheus-community.github.io/helm-charts)
- **Version:** `29.0.0` (Latest as of May 2026)
- **Sync Wave:** `5` (Applied before operators in Wave 6)

## 4. References
- [Prometheus Operator GitHub](https://github.com/prometheus-operator/prometheus-operator)
- [VictoriaMetrics Converter Guide](https://docs.victoriametrics.com/operator/design/#prometheus-converter)
