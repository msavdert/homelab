# cert-manager: Automated Certificate Management for Homelab

This documentation explains the design, implementation, and best practices for **cert-manager** (v1.20.2) in this homelab environment.

---

## 1. What is cert-manager?

`cert-manager` is a native Kubernetes certificate management controller. It builds upon Kubernetes by introducing several Custom Resource Definitions (CRDs) like `Certificates`, `Issuers`, and `ClusterIssuers`.

### Why is it mandatory in this Homelab?
Modern Kubernetes operators (like **VictoriaMetrics** and **CloudNativePG**) use **Admission Webhooks**. These webhooks allow the operator to validate or mutate resources before they are applied to the cluster. Kubernetes requires these webhooks to communicate over **HTTPS**.
- **The Problem**: Manually managing these internal certificates is a maintenance nightmare.
- **The Solution**: `cert-manager` automates the entire lifecycle (issuance and renewal) of these certificates, ensuring operators never stop working due to expired TLS.

---

## 2. Implementation Strategy (GitOps)

We deploy `cert-manager` via **ArgoCD** using the official **OCI-based Helm Chart**.

### Key Configuration Decisions:
- **OCI Helm Chart**: We use `quay.io/jetstack/charts/cert-manager`. In 2026, OCI charts are the standard for performance and security.
- **CRD Management**: We set `installCRDs: true`. To prevent ArgoCD from failing due to the massive size of these CRDs, we enable **`ServerSideApply=true`** in the sync options.
- **Sync Waves (-8)**: `cert-manager` is a foundation service. By assigning it to wave `-8`, we ensure it is fully ready before any other operators (like VictoriaMetrics) attempt to request certificates.

---

## 3. Issuers: The "Notaries" of the Cluster

We use two types of Issuers to balance security and convenience.

### A. ClusterIssuer: `selfsigned-issuer` (Internal)
Used for internal service-to-service communication where a public CA isn't needed.
- **Use case**: Admission webhooks for operators.
- **Config**: A simple `selfSigned: {}` block.

### B. ClusterIssuer: `letsencrypt-cloudflare` (Public)
Used for services exposed to the internet (e.g., Grafana, Nextcloud).
- **Challenge Type**: **DNS-01**.
- **Why DNS-01?**: Unlike HTTP-01, DNS-01 doesn't require opening port 80 to the internet. Since this is a homelab, we use **Cloudflare** to prove domain ownership by automatically creating temporary DNS TXT records.
- **Token Security**: The Cloudflare API token is stored as a Kubernetes Secret, which can be managed via 1Password or Sealed Secrets.

---

## 4. Best Practices Applied

1. **Resource Parity**: Although lightweight, we set `requests` equal to `limits` to ensure the controller is never throttled during high-load API operations.
2. **Monitoring**: Enabled the `prometheus.servicemonitor` flag. This allows **VictoriaMetrics** to automatically scrape cert-manager health metrics, alerting us if a certificate renewal fails.
3. **Webhook Redundancy**: In production, `replicaCount` for the webhook component should be at least 2 to prevent API blocking during node restarts.
4. **Separation of Concerns**: Issuers are managed in a separate ArgoCD Application (`cert-manager-issuers`) to ensure the Controller is ready before the Issuers are created.

---

## 5. Reference & Further Reading

- [Official cert-manager Documentation](https://cert-manager.io/docs/)
- [GitOps Installation Best Practices](https://cert-manager.io/docs/installation/continuous-deployment-and-gitops/)
- [Cloudflare DNS-01 Configuration Guide](https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/)
- [Jetstack OCI Chart Migration Guide](https://blog.jetstack.io/blog/cert-manager-oci-helm-charts/)

---
*Last Updated: 2026-05-01*
