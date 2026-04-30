# Longhorn Storage Integration Guide (Talos Linux & Proxmox)

This document outlines the step-by-step integration of Longhorn distributed storage into the homelab cluster. The goal is to ensure a fully automated and reproducible setup where a `terraform destroy` followed by `terraform apply` results in a cluster ready for Longhorn storage.

## 🛠 Infrastructure Layer (Terraform & Talos)

To support Longhorn on Talos Linux, specific host-level configurations must be handled during the provisioning phase.

### 1. Proxmox Virtual Machine Configuration
Best practices for Proxmox disks to ensure Longhorn performance and data integrity:
- **Dedicated Data Disk**: Add a second disk (e.g., `/dev/sdb`) to worker nodes specifically for Longhorn. This separates OS and storage data.
- **Controller**: Use **VirtIO SCSI** or **SCSI**.
- **Discard**: Set to `on` (required for Longhorn to reclaim space on the Proxmox thin-provisioned storage).
- **SSD Emulation**: Enable if the underlying Proxmox storage is an SSD.
- **IO Thread**: Enable for better parallel I/O performance.

### 2. Talos System Extensions
Longhorn requires binaries not present in the default Talos image. These must be added to the `customization.systemExtensions` block in the machine configuration:
- `siderolabs/iscsi-tools`: Required for iSCSI operations (Longhorn volume attachment).
- `siderolabs/util-linux-tools`: Required for disk utilities like `fstrim`.

### 3. Kubelet Extra Mounts
Talos is an immutable OS. Longhorn needs host-path access to persist data and manage volumes. The following bind mount must be configured in the `machine.kubelet.extraMounts` section:
- **Source**: `/var/lib/longhorn`
- **Destination**: `/var/lib/longhorn`
- **Options**: `bind`, `rshared`, `rw`

---

## 🚀 Application Layer (Argo CD GitOps)

Once the infrastructure is ready, Longhorn should be deployed via Argo CD to follow GitOps principles.

### 1. Argo CD Application Manifest
Create a new application manifest (e.g., `apps/production/longhorn.yaml`):
- **Repo URL**: `https://charts.longhorn.io/`
- **Chart**: `longhorn`
- **Target Revision**: `v1.11.1` (or latest stable)
- **Namespace**: `longhorn-system`

### 2. Critical Helm Values
To ensure a smooth sync with Argo CD, set the following values:
- `preUpgradeChecker.jobEnabled: false`: Prevents Argo CD from getting stuck during upgrade checks.
- `persistence.defaultClassReplicaCount: 3`: Adjust based on your worker node count.
- `defaultSettings.backupTarget`: (Optional) Configure S3/MinIO for backups.

---

## 📚 Official References & Key Takeaways

### [Talos Linux Support (Longhorn Docs)](https://longhorn.io/docs/1.11.1/advanced-resources/os-distro-specific/talos-linux-support/)
- **Critical**: Talos upgrades **WILL WIPE** `/var/lib/longhorn` unless the `--preserve` flag is used.
- **Security**: Longhorn requires `enforce: "privileged"` pod security admission for its namespace.

### [Argo CD Installation (Longhorn Docs)](https://longhorn.io/docs/1.11.1/deploy/install/install-with-argocd/)
- Recommends using the official Helm repository.
- Suggests setting the `syncPolicy` with `CreateNamespace=true`.

### [Longhorn on Proxmox (ComputingForGeeks)](https://computingforgeeks.com/longhorn-storage-kubernetes-proxmox/)
- Highlights the importance of the `Discard` flag in Proxmox to prevent disk bloat.
- Recommends using a dedicated storage network if available.

---

## 🔄 Lifecycle Management
By embedding the extensions and mounts into the Terraform templates (`.tftpl`), any future cluster recreation via `terraform apply` will automatically prepare the nodes for Longhorn. The Argo CD application will then automatically deploy the storage engine once the cluster is reachable.
