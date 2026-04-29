# GitOps Homelab with Proxmox, Talos, and Terraform

This repository contains the Infrastructure as Code (IaC) and GitOps configuration for a production-grade homelab. It automates the deployment of a Talos Linux Kubernetes cluster on Proxmox VE and manages applications using ArgoCD.

## Project Architecture

The project is divided into two main infrastructure layers:

1.  **Infrastructure Layer (`terraform/proxmox`)**: Responsible for provisioning virtual machines on Proxmox VE using the modern `bpg/proxmox` provider, installing Talos Linux from ISO without requiring SSH access, and bootstrapping the Kubernetes control plane.
2.  **Application Layer (`terraform/kubernetes`)**: Responsible for configuring the Kubernetes cluster, including namespaces, secrets, and core services like ArgoCD and Cilium via Helm.

## Directory Structure

```bash
.
├── apps/                   # ArgoCD Application manifests (GitOps)
│   ├── base/               # Base application definitions
│   └── production/         # Production-specific overlays
├── terraform/
│   ├── proxmox/            # Infrastructure provisioning on Proxmox
│   └── kubernetes/         # Kubernetes configuration and Helm releases
└── README.md               # This file
```

## Component Stack & Versions

| Component | Version | Release Date | Description |
| :--- | :--- | :--- | :--- |
| **Talos Linux** | `v1.13.0` | April 27, 2026 | Security-focused, immutable Linux distribution for Kubernetes. |
| **Kubernetes** | `v1.36.0` | April 22, 2026 | Container orchestration platform. |
| **Cilium** | `v1.19.3` | April 15, 2026 | eBPF-based networking, observability, and security. |
| **ArgoCD** | `v9.5.6` | April 27, 2026 | Declarative GitOps continuous delivery tool for Kubernetes. |
| **Gateway API** | `v1.5.1` | March 13, 2026 | Modern, expressive, and extensible routing for Kubernetes. |
| **Terraform** `hashicorp/hcl` | `v1.15.0` | April 29, 2026 | Infrastructure as Code tool. |
| **Proxmox Provider** `bpg/proxmox` | `v0.104.0` | April 25, 2026 | Modern, API-first Terraform provider for Proxmox VE. |

## Keeping Versions Updated

To ensure your project remains up-to-date:
1.  **Providers**: Run `terraform init -upgrade` to update provider versions.
2.  **Factory Images**: For Talos Linux, visit [factory.talos.dev](https://factory.talos.dev/) to generate the latest `schematic ID` for your required extensions (e.g., `qemu-guest-agent`). Ensure you are using the `nocloud-amd64.iso` image for Cloud-Init static IP support.
3.  **Helm Charts**: Regularly check for new chart versions and update the `version` field in your Terraform resources.
4.  **Gateway API**: To automatically update Gateway API CRDs to the latest version, run the following command in the project root:
    ```bash
    curl -L "https://github.com/kubernetes-sigs/gateway-api/releases/download/$(curl -s https://api.github.com/repos/kubernetes-sigs/gateway-api/releases/latest | grep -Po '\"tag_name\": \"\K[^\"]*')/standard-install.yaml" -o terraform/proxmox/gateway-api/gateway-api-crds.yaml
    ```

## Prerequisites

- **Proxmox VE**: A running Proxmox instance with API access (SSH is **not** required).
- **Terraform**: For infrastructure management.
- **Talosctl**: For interacting with Talos Linux nodes.
- **Kubectl**: For Kubernetes cluster management.

## Getting Started

### 1. Infrastructure Provisioning
Navigate to the Proxmox directory, set up your variables using the provided example, and initialize the infrastructure. For detailed information on the provisioning process, see the [Proxmox Infrastructure README](terraform/proxmox/README.md).

```bash
cd terraform/proxmox
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Proxmox credentials
terraform init
terraform apply
```
This will create the VMs (1 Control Plane, 3 Workers by default), install Talos Linux seamlessly with static IPs, and output the `kubeconfig` and `talosconfig`.

### 2. Kubernetes Configuration
Once the cluster is up, apply the Kubernetes configuration. For details on namespaces, secrets, and Helm releases, see the [Kubernetes Cluster README](terraform/kubernetes/README.md).

```bash
cd ../kubernetes
terraform init
terraform apply
```
This will install ArgoCD and Cilium, enabling the GitOps workflow.

## Features

- **SSH-less Provisioning**: Fully automated deployment relying solely on the Proxmox API and Cloud-Init on IDE0.
- **Talos Linux**: Security-focused, immutable, and minimal Linux distribution for Kubernetes.
- **GitOps**: Automated application lifecycle management using ArgoCD.
- **Cilium**: High-performance networking and security with eBPF.
- **Infrastructure as Code**: Fully reproducible environment using Terraform.

## License

This project is licensed under the MIT License.
