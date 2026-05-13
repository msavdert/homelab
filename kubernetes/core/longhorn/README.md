# Longhorn Storage Configuration

This component provides highly available block storage for the cluster, optimized for Talos Linux and single-node persistence constraints.

## 1. Overview
Longhorn is used for distributed block storage. In this environment, it is configured to work with Proxmox-managed ZFS backends while providing Kubernetes-native persistent volumes.

## 2. Installation & Versioning
- **Method:** ArgoCD / Kustomize (Helm Inflation).
- **Source:** [charts.longhorn.io](https://charts.longhorn.io)
- **Version:** `v1.7.2`
  - *Determination:* Selected via `helm search repo longhorn/longhorn` for the latest stable 1.7.x release. This version is verified for compatibility with Talos Linux v1.7+ and Cilium eBPF.
- **Sync Wave:** `1` (Applied after networking/secrets).

## 3. Configuration Rationale (AGENTS.md Compliance)
- **Replica Count (1):** As per `AGENTS.md`, `defaultReplicaCount` is set to `1`. Since the underlying Proxmox host uses ZFS, software-level replication is disabled to prevent write amplification.
- **Data Locality:** Disabled globally to allow flexible pod scheduling, but specifically overridden for databases.
- **Pod Security:** Namespace labeled with `privileged` enforcement to allow the manager and engine to interact with host devices.

## 4. Custom StorageClasses
- **`longhorn-db`**: 
  - `replicaCount: 1`
  - `dataLocality: strict-local`
  - *Rationale:* Ensures database data stays on the same node as the Pod for minimum latency (Shared-Nothing architecture).

## 5. Troubleshooting & Best Practices
- **ArgoCD Sync:** Global `ignoreDifferences` are applied in `argocd-cm` for CRDs to handle `preserveUnknownFields` diffs introduced in ArgoCD 3.0.
- **Talos:** Requires `iscsi-tools` and `util-linux-tools` system extensions.

## 6. References
- [Longhorn Official Docs](https://longhorn.io/docs/1.7.2/)
- [Talos Storage Guide](https://www.talos.dev/v1.7/kubernetes-guides/configuration/storage/longhorn/)
