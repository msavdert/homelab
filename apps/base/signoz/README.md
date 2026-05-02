# SigNoz Observability Stack

SigNoz is an open-source observability platform that provides Metrics, Traces, and Logs in a single pane of glass. It is built on top of OpenTelemetry and uses ClickHouse as its primary storage engine for high-performance telemetry data processing.

## 🚀 Installation Overview

In this repository, SigNoz is deployed using **ArgoCD** with a **Multi-Source** strategy. This allows us to combine the official Helm chart with local customizations while keeping the repository clean.

### Deployment Structure

- **Official Chart**: `https://charts.signoz.io` (Managed in `apps/production/signoz.yaml`)
- **Custom Values**: `apps/base/signoz/values.yaml`
- **Namespace**: `signoz`

## 🛠 Configuration Details

### 💾 Storage (Longhorn)
SigNoz requires persistent storage for three main components:
- **ClickHouse**: Stores the bulk of telemetry data.
- **Zookeeper**: Manages ClickHouse coordination.
- **Query Service**: Stores internal configuration and metadata.

All components are configured to use the `longhorn` storage class for automated volume provisioning and replication.

- **TLS**: Automated via `cert-manager` using the `letsencrypt-prod` issuer.

### 🔐 1Password Integration (Root Bootstrap)
This deployment uses `OnePasswordItem` to securely bootstrap the root admin account. The credentials are pulled from the `SigNoz` item in the `homelab` vault.
- **Enabled**: `SIGNOZ_USER_ROOT_ENABLED: "true"`
- **Secret**: `signoz-admin-credentials` (Created via `apps/base/signoz/onepassword-item.yaml`)

## 🏁 Post-Installation Steps

1. **Initial Setup**: Once the application is synced in ArgoCD and pods are ready, visit `https://signoz.savdert.com`.
2. **Onboarding**: Follow the on-screen instructions to create the initial admin account.
3. **Data Ingestion**:
   - SigNoz provides an OTel Collector out of the box.
   - Point your applications to `signoz-otel-collector.signoz.svc.cluster.local:4317` (gRPC) or `4318` (HTTP) for telemetry ingestion.

## 📊 Cluster Monitoring (k8s-infra)

We use the `k8s-infra` chart to monitor the health of our Kubernetes cluster. This component collects:
- **Node Metrics**: CPU, RAM, Disk usage.
- **Container Logs**: Automated log collection from all pods.
- **Kubelet Stats**: Resource usage per pod/node.
- **K8s Events**: Cluster-level events (pod restarts, errors, etc.)

Configuration is managed in `apps/base/k8s-infra/values.yaml`.

## 💡 Best Practices

## 📚 Resources

- [Official SigNoz Documentation](https://signoz.io/docs/)
- [SigNoz GitHub Repository](https://github.com/SigNoz/signoz)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [ArgoCD Multi-Source Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/)

---
*Note: This README is excluded from ArgoCD sync via the `directory.exclude` property in the Application manifest.*
