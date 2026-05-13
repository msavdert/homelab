# OpenTelemetry Operator

The central management layer for telemetry collection, processing, and exporting (Metrics, Logs, Traces).

## 1. Overview
The OTel Operator is the cornerstone of our "OTel-First" observability strategy. It manages `OpenTelemetryCollector` instances and provides automatic instrumentation for applications.

## 2. Installation Details
- **Method:** ArgoCD / Kustomize (Helm Inflation).
- **Source:** [open-telemetry.github.io/opentelemetry-helm-charts](https://open-telemetry.github.io/opentelemetry-helm-charts)
- **Version:** `v0.151.0` (Chart `0.113.0`)
- **Sync Wave:** `7`

## 3. Configuration Rationale
- **Admission Webhooks:** Enabled and integrated with `cert-manager`. This is required for injecting OTel agents into pods automatically.
- **OTel-First Strategy:** All telemetry (including logs and metrics) will be routed through OTel Collectors before being stored in VictoriaMetrics or Clickhouse.

## 4. References
- [OpenTelemetry Operator Documentation](https://opentelemetry.io/docs/kubernetes/operator/)
- [Talos Linux & OTel Guide](https://www.talos.dev/v1.7/kubernetes-guides/configuration/opentelemetry/)
