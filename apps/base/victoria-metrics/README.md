# VictoriaMetrics Observability Stack

This folder contains the GitOps manifests for the VictoriaMetrics monitoring stack, managed via ArgoCD.

## Architecture & Design Decisions

The stack is designed to be fully automated and self-healing. To achieve "zero manual intervention" during cluster bootstrapping, we implemented several critical configurations:

### 1. Dependency Management (ArgoCD Sync Waves)
The observability stack has strict dependencies on other infrastructure components. We use ArgoCD sync-waves to ensure the correct order:
- **Wave -10**: `prometheus-operator-crds` & `gateway-api-crds`. Critical CRDs must exist before any operator starts.
- **Wave -8**: `cert-manager`. Provides TLS certificates for admission webhooks.
- **Wave -4**: `victoria-metrics-stack`. The main monitoring components.

### 2. VictoriaMetrics Operator & Admission Webhooks
The operator uses Admission Webhooks for resource validation. 
- **Cert-Manager Integration**: We delegate certificate management to `cert-manager`.
- **Manual Annotation**: Due to limitations in some Helm chart versions, we explicitly add `cert-manager.io/inject-ca-from` to force CA bundle injection. This prevents the "unknown authority" TLS errors common in fresh installs.

### 3. Grafana Persistence (SQLite on Longhorn)
Running SQLite on network-attached storage (Longhorn) requires specific optimizations to prevent `SQLITE_BUSY` (database is locked) errors:
- **WAL Mode**: Enabled `database.wal: true` in `grafana.ini` to allow concurrent read/write operations.
- **Permissions**: Explicitly set `podSecurityContext` to UID/GID `472` to ensure Grafana has write access to the persistent volume.
- **Probes**: Relaxed `readinessProbe` to give the database enough time for migrations during cold starts.

### 4. Secret Management (1Password)
Admin credentials for Grafana are managed via 1Password:
- **OnePasswordItem**: A CRD that syncs credentials from the `homelab` vault.
- **Keys**: Expects `admin-user` and `admin-password` fields in the 1Password item.

## Prerequisites

Before deploying this stack, ensure the following applications are running in your cluster:
1. **Longhorn**: For persistent storage.
2. **cert-manager**: For webhook certificate management.
3. **1Password Connect**: For secret synchronization.

## Installation from Scratch
The entire stack is declarative. To re-install:
1. Apply the `app-of-apps` (or the specific production manifests).
2. ArgoCD will respect the sync-waves.
3. The `prometheus-operator-crds` will install first.
4. The VictoriaMetrics operator will start, request a certificate from `cert-manager`, and initialize the stack without manual `kubectl` intervention.

## Troubleshooting
- **Progressing State**: If the app stays in `Progressing` but pods are `Healthy`, it's likely a health-check mismatch in ArgoCD for custom resources like `VMSingle`. The system is technically operational.
- **Webhook Errors**: If you encounter TLS errors during an *upgrade*, manually delete the `ValidatingWebhookConfiguration` to allow the new certificate to be injected. (This is not required for a fresh install).
