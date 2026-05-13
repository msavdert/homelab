# cert-manager Deployment

This directory manages the configuration for **cert-manager**, the native Kubernetes certificate management controller.

## Purpose

In this homelab, `cert-manager` is primarily used for **internal cluster certificate management**. 

> [!IMPORTANT]
> **Scope**: This installation is NOT intended for managing public SSL certificates for external websites. It provides a secure internal PKI for cluster components (e.g., OpenTelemetry Operator webhooks).

## Deployment Strategy

We use **ArgoCD** with **Kustomize** to deploy cert-manager via its official Helm chart.

- **AppSet**: `kubernetes/argocd-apps/core-appset.yaml`
- **Chart Version**: `v1.20.2` (Pinned)
- **Namespace**: `cert-manager`

### Key Configuration (`values.yaml`)
- `installCRDs: true`: Managed via Helm for easier upgrades.
- `prometheus.enabled: true`: Exposes metrics for cluster observability.
- `resources`: Optimized requests/limits for homelab stability.

### Internal PKI (Issuers)
We have configured a two-tier internal CA system in `issuers.yaml`:

1.  **selfsigned-issuer**: A `ClusterIssuer` that can sign basic self-signed certificates.
2.  **root-ca**: A `Certificate` resource signed by the `selfsigned-issuer` that acts as our internal Root CA.
3.  **internal-ca-issuer**: A `ClusterIssuer` using the `root-ca` secret. Use this issuer for all internal service certificates.

## Best Practices

### Server-Side Apply
Following our `AGENTS.md` rules, we use `ServerSideApply=true` in ArgoCD. This is mandatory for `cert-manager` because its CRDs are extremely large and will fail with standard `kubectl apply`.

### Namespace Management
The namespace `cert-manager` is explicitly defined in `namespace.yaml` and included in `kustomization.yaml` for clear visibility and consistent application of labels/annotations.

## Usage

To request an internal certificate, use the `internal-ca-issuer`:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-app-cert
  namespace: my-namespace
spec:
  secretName: my-app-tls
  issuerRef:
    name: internal-ca-issuer
    kind: ClusterIssuer
  commonName: my-app.svc.cluster.local
  dnsNames:
    - my-app.my-namespace.svc.cluster.local
```

## References
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [GitOps Best Practices](https://cert-manager.io/docs/installation/continuous-deployment-and-gitops/)
