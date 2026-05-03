# Deployment Guide

This guide describes how to deploy the unified VictoriaMetrics monitoring stack using ArgoCD.

## Prerequisites
- **ArgoCD**: Installed and functional.
- **Cert-Manager**: Installed (required for VM Operator admission webhooks).
- **Longhorn**: Installed and configured as the default StorageClass (or explicitly specified).
- **1Password Connect**: Installed (required for Grafana credentials via `OnePasswordItem`).

## Step-by-Step Installation

### 1. Prepare Credentials
Ensure you have a 1Password item named `Grafana` in your `homelab` vault with `user` and `password` fields. The `OnePasswordItem` resource in `apps/base/victoria-metrics/onepassword-item.yaml` will sync these to a Kubernetes Secret.

### 2. Enable the Application
Rename the manifest (if you haven't already) and ensure it's in the `apps/production/` directory.

```bash
# The manifest is located at apps/production/victoria-metrics.yaml
```

### 3. Sync via ArgoCD
ArgoCD will automatically pick up the new Application. You can manually trigger a sync:

```bash
argocd app sync victoria-metrics-stack
```

## ArgoCD Specific Configurations

To avoid common synchronization issues with the VictoriaMetrics Operator in ArgoCD, the following configurations have been implemented in the `Application` manifest:

### Respect Ignore Differences
We use `RespectIgnoreDifferences=true` to ensure that ArgoCD respects our exclusions during the `kubectl apply` phase.

### Ignore Differences for Webhooks
The VM Operator generates self-signed certificates (or uses Cert-Manager) for its admission webhooks. ArgoCD often sees the `caBundle` and the secret data as "out of sync". We ignore these fields:

```yaml
ignoreDifferences:
  - group: admissionregistration.k8s.io
    kind: ValidatingWebhookConfiguration
    name: vm-victoria-metrics-operator-admission
    jqPathExpressions:
      - '.webhooks[]?.clientConfig.caBundle'
  - group: ""
    kind: Secret
    name: vm-victoria-metrics-operator-validation
    jsonPointers:
      - /data
```

### Server Side Apply
Due to the large size of some Grafana dashboards (especially `node-exporter-full`), `ServerSideApply=true` is enabled to bypass the 262KB annotation limit of Kubernetes.

## Verification
1. Check the `monitoring` namespace: `kubectl get pods -n monitoring`
2. Verify the Cluster components: `kubectl get vmcluster -n monitoring`
3. Access Grafana: `https://grafana.savdert.com`
