# Proxmox & Talos Infrastructure (Terraform)

This directory contains the Infrastructure as Code (IaC) required to bootstrap the GitOps HomeLab. It provisions the virtual machines on Proxmox VE and automatically installs and configures Talos Linux.

## Architecture
- **Hypervisor:** Proxmox VE
- **OS:** Talos Linux (Factory Schematic image)
- **Topology:** 1 Control Plane (2 vCPU, 8GB RAM), 4 Workers (4 vCPU, 16GB RAM)
- **Networking:** Cilium CNI (kube-proxy replacement in strict mode)
- **Storage:** Dedicated 200GB disks on Worker nodes mapped for Longhorn.
- **Observability:** eBPF (Beyla) support enabled via `machine_config_patches`.
- **State Backend:** AWS S3 (or S3-compatible storage like OCI/MinIO).

## Prerequisites
- Proxmox VE installed and accessible.
- An S3 bucket for Terraform state storage.
- A Proxmox API Token (`proxmox_api_token`).
- `terraform` CLI installed.

## Setup Instructions

### 1. Identify Your Proxmox Configuration
Before applying, you need to configure your Proxmox-specific variables. If you are unsure what values to use, you can run the following commands on your Proxmox host (`root@pve`):

#### Finding the Node Name (`proxmox_target_node`)
```bash
pvesh get /nodes
```
Look at the `node` column in the output. Typically, this is `pve`.

#### Finding Storage Pools (`proxmox_iso_storage` and `proxmox_vm_storage`)
```bash
pvesm status
```
- **ISO Storage (`proxmox_iso_storage`):** Look for a storage pool that supports `iso,vztmpl` (usually `dir` type). Typically, this is `local`.
- **VM Storage (`proxmox_vm_storage`):** Look for a storage pool that supports `rootdir,images` (usually `zfspool` or `lvmthin` type). Typically, this is `local-zfs` or `local-lvm`.

#### Finding the Network Bridge (`proxmox_network_bridge`)
If you are using SDN (Software Defined Networking) with NAT, find your vnets:
```bash
pvesh get /cluster/sdn/vnets
```
Look at the `vnet` column (e.g., `vnet0`).

#### Finding the Network CIDR and Gateway (`network` and `network_gateway`)
If using SDN, inspect the subnet details:
```bash
pvesh get /cluster/sdn/vnets/vnet0/subnets
```
This will output the `cidr` (e.g., `10.0.0.0/24`) and `gateway` (e.g., `10.0.0.1`) that you should use in your `terraform.tfvars`.

### 2. Configure Variables
Copy the example variables file and adjust the endpoint and network details based on the commands above:
```bash
cp terraform.tfvars.example terraform.tfvars
```

### 3. Set Environment Variables
Terraform requires credentials for both Proxmox and your S3 backend. Set these securely in your shell:
```bash
# Proxmox API Token
export TF_VAR_proxmox_api_token="root@pam!token=your-uuid"

# S3 Backend Credentials
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
```

### 4. Initialize and Plan
Initialize the Terraform directory to download providers and setup the S3 backend:
```bash
terraform init
```

Run a plan to verify the resources that will be created:
```bash
terraform plan
```

### 5. Apply and Bootstrap
Once you are satisfied with the plan, apply the configuration:
```bash
terraform apply
```

### 6. Accessing the Cluster
After a successful apply, the configuration files will be automatically generated in this directory.
You can verify cluster health using `talosctl`:
```bash
export TALOSCONFIG="./talosconfig"
export KUBECONFIG="./kubeconfig"

talosctl -n 10.0.0.10 dmesg
kubectl get nodes
```
