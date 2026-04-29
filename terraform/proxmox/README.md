# Proxmox Infrastructure Provisioning

This directory contains the Terraform code required to provision the base infrastructure for the Talos Linux Kubernetes cluster on Proxmox VE.

## Overview

The infrastructure layer uses the modern `bpg/proxmox` provider and handles the following tasks:
- Downloading the required Talos Linux ISO images to Proxmox storage using declarative resources.
- Generating Talos machine secrets and configurations.
- Provisioning Virtual Machines (VMs) on Proxmox directly from the ISO using the `proxmox_virtual_environment_vm` resource.
- Assigning static IP addresses via a Cloud-Init (`nocloud`) drive attached to `ide0`.
- Bootstrapping the Talos cluster using the Talos API.
- Injecting initial Kubernetes manifests (like Cilium and Gateway API CRDs) into the Talos machine configuration.

## Talos Best Practices on Proxmox

This project follows the official [Talos Linux Proxmox Best Practices](https://docs.siderolabs.com/talos/v1.13/platform-specific-installations/virtualized-platforms/proxmox) and introduces an optimized zero-touch workflow.

| Recommendation | Status | Project Implementation |
| :--- | :--- | :--- |
| **No SSH Requirement** | [x] | Cloud-Init is mapped to `ide0` while the ISO maps to `ide2`, preventing conflicts and bypassing the need for SSH-based `qm importdisk` operations. |
| **BIOS: OVMF (UEFI)** | [x] | `bios = "ovmf"` and `efi_disk` configured for modern firmware. |
| **Machine: q35** | [x] | `machine = "q35"` configured for PCIe-based machine type. |
| **CPU Type: host** | [x] | `cpu { type = "host" }` used for maximum performance. |
| **Disk Controller: VirtIO SCSI** | [x] | Standard `scsi0` used with `virtio` block configuration. |
| **Discard (TRIM): Enabled** | [x] | `discard = "on"` enabled for SSD performance. |
| **Guest Agent: Enabled** | [x] | `agent { enabled = true }` and `siderolabs/qemu-guest-agent` included via the factory image. |

## Cluster Architecture Scenarios

This project is designed to be flexible, supporting multiple deployment strategies depending on your resources.

### Scenario A: Shared Nodes (Control Plane + Worker)
In this scenario, all nodes act as both Control Plane and Workers. This is ideal for small clusters (3-5 nodes) to maximize resource utilization.
- **Configuration:** Fill `controlplanes` map in `node_data` and leave `workers` empty.
- **Note:** Control plane nodes are automatically untainted by this project's configuration to allow scheduling workloads.

### Scenario B: Dedicated Nodes (Separate Control Plane and Workers) - Current Default
In this scenario, Control Plane nodes are dedicated to managing the cluster, and Workers are dedicated to running applications. This is recommended for production environments.
- **Configuration:** Fill both `controlplanes` and `workers` maps in `node_data`.
- **Note:** Control plane nodes will typically remain tainted (meaning apps won't run on them) unless specified otherwise.

### Why use a Map for Node Configuration?
Instead of a simple `node_count` variable, we use a Map with IP addresses as keys because:
1.  **Predictability:** Each node is assigned a specific static IP via the `nocloud` provider.
2.  **Granular Control:** Allows specifying different hardware settings per specific node.
3.  **Safety:** When scaling down, removing a specific IP from the map ensures only *that* specific VM is destroyed, preventing accidental loss of the "wrong" node.

## Proxmox Variable Mapping Guide

To fill in the `terraform.tfvars` correctly, use the following Proxmox commands and map their outputs:

### 1. Identify Target Node
**Command:** `pvesh get /nodes`
- **Variable:** `proxmox_target_node`
- **Mapping:** Use the value from the `node` column (e.g., `prox`).

### 2. Identify Storage Pool
**Command:** `pvesh get /nodes/<NODE_NAME>/storage`
- **Variable:** `proxmox_storage_device`
- **Mapping:** Use the value from the `storage` column where `content` includes `iso` and `images` (e.g., `local`).

### 3. Identify Network Configuration
**Command:** `pvesh get /cluster/sdn/vnets`
- **Variable:** `proxmox_network_bridge` (inside `terraform.tfvars`)
- **Mapping:** Use the `vnet` or bridge name (e.g., `vnet1` or `vmbr0`).

## File Details

- **`providers.tf`**: Configures the modern `bpg/proxmox` and `siderolabs/talos` providers via API integration.
- **`virtual_machines.tf`**: Defines the `proxmox_virtual_environment_download_file` to cache the ISO, and provisions the VMs with specific `ide0` Cloud-Init blocks for automated IP injection.
- **`talos_linux.tf`**: 
    - Generates cluster secrets.
    - Defines machine configurations for `controlplane` and `worker` types.
    - Applies machine configurations to the nodes via the Talos API.
    - Executes the bootstrap process on the first control plane node.
    - Generates the `kubeconfig` and `talosconfig` files.
- **`helm_templates.tf`**: Uses the `helm_template` data source to pre-render the Cilium CNI manifests, which are then included in the Talos machine configuration for "hands-free" networking setup.
- **`variables.tf`**: Contains all configurable parameters such as Proxmox API endpoints, node counts, hardware specs, and network settings.

## Configuration

Most configuration is handled via the `terraform.tfvars` file (not included in version control since it contains secrets). You should define your variables based on the `terraform.tfvars.example` file.

## Usage

1.  Copy the example variables and insert your tokens:
    ```bash
    cp terraform.tfvars.example terraform.tfvars
    ```
2.  Initialize the workspace:
    ```bash
    terraform init
    ```
3.  Review the plan:
    ```bash
    terraform plan
    ```
4.  Apply the changes:
    ```bash
    terraform apply
    ```

## Post-Installation

After a successful apply, you will find `kubeconfig` and `talosconfig` files generated in your local directory. These are used to interact with the cluster securely.
