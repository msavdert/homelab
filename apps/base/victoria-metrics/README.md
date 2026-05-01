# VictoriaMetrics K8s Stack: Homelab Deployment & Best Practices

This document provides a detailed guide for deploying the **VictoriaMetrics K8s Stack** (the modern, high-performance alternative to `kube-prometheus-stack`) using **ArgoCD**. It is optimized for a homelab environment with a focus on resource efficiency and long-term stability.

---

## 1. Why VictoriaMetrics?

While `kube-prometheus-stack` is the industry standard, **VictoriaMetrics** offers significant advantages for homelab users:
- **Efficiency**: 3-6x less RAM and CPU usage compared to Prometheus.
- **Storage**: Up to 10x better disk compression (ideal for small NVMe/SSD drives).
- **Simplicity**: No need for complex add-ons like Thanos for long-term retention.
- **Compatibility**: 100% compatible with Prometheus alerts and Grafana dashboards.

---

## 2. Installation via ArgoCD

The recommended way to deploy is using the `victoria-metrics-k8s-stack` Helm chart.

### ArgoCD Application Manifest
See `apps/production/victoria-metrics.yaml`.

```yaml
# Summary of configuration
vmsingle: enabled: true
retentionPeriod: "6"
sync-wave: "-4"
```

---

## 3. Monitoring CloudNativePG (CNPG)

VictoriaMetrics supports standard `PodMonitor` and `ServiceMonitor` resources used by the Prometheus Operator.

### Automatic Discovery
The `VMAgent` will detect any `PodMonitor` created by CNPG (ensure `enablePodMonitor: true` is set in the Postgres cluster YAML) and start scraping PostgreSQL metrics immediately.

---

## 4. Best Practices

- **Resource Allocation**: Requests = Limits. Use Integer CPUs (e.g., `1` instead of `500m`).
- **Storage**: Use a fast StorageClass (e.g., Longhorn).
- **MetricsQL**: Use the enhanced query language for better performance and extra functions.

---

*Last Updated: 2026-05-01*
