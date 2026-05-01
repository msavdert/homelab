# cert-manager: GitOps Deployment & Homelab Best Practices

This guide covers the deployment of **cert-manager** (v1.20.2) using **ArgoCD**. It is designed for a homelab environment where security and automation are priorities.

---

## 1. Overview

`cert-manager` is a native Kubernetes certificate management controller. It helps in issuing certificates from various sources like Let's Encrypt, HashiCorp Vault, Venafi, a simple signing key pair, or self-signed.

In this homelab, we use it to:
- Secure internal Operator webhooks (VictoriaMetrics, CNPG).
- Provide real TLS certificates for exposed services via **Cloudflare DNS-01**.

---

## 2. Installation via ArgoCD

Using the official OCI Helm chart is the best practice for 2026.

### ArgoCD Application Manifest
See `apps/production/cert-manager.yaml`.

```yaml
# Summary of sync configuration
installCRDs: true
sync-wave: "-8"
ServerSideApply: true
```

---

## 3. Configuration (Issuers)

After installing `cert-manager`, you need to define a **ClusterIssuer** to actually issue certificates.

### A. Internal Self-Signed (For Webhooks)
Required for many operators to function. See `issuers.yaml` in this directory.

### B. Let's Encrypt with Cloudflare (For Public Services)
Best practice for homelabs to avoid opening ports 80/443 for HTTP-01 challenges.

1. **Create a Secret with your Cloudflare API Token**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token-secret
  namespace: cert-manager
type: Opaque
stringData:
  api-token: <YOUR_CLOUDFLARE_TOKEN>
```

2. **Create the ClusterIssuer**:
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-cloudflare
spec:
  acme:
    email: your-email@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-cloudflare-account-key
    solvers:
    - dns01:
        cloudflare:
          email: your-email@example.com
          apiTokenSecretRef:
            name: cloudflare-api-token-secret
            key: api-token
```

---

## 4. Troubleshooting

- **Check API**: `kubectl get clusterissuers`
- **Challenges**: `kubectl get challenges -A`
- **Orders**: `kubectl get orders -A`

---

*Last Updated: 2026-05-01*
