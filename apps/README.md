# GitOps Application Management with ArgoCD

Welcome to the GitOps layer of your homelab! This directory follows the **App of Apps pattern**, which is the industry standard for managing multiple applications in a single Kubernetes cluster using ArgoCD.

## 🧠 Core Concepts

### What is GitOps?
GitOps is a practice where the entire state of your infrastructure and applications is defined in Git. If you want to deploy a new version of an app or change its configuration, you don't use `kubectl`. Instead, you push a commit to this repository. ArgoCD acts as the "controller" that synchronizes the state between Git and Kubernetes.

### The "App of Apps" Pattern
Instead of manually creating an ArgoCD Application for every single tool (Grafana, Nextcloud, etc.), we use a **Root Application**. This Root App tracks a specific folder (in our case, `apps/production/`) and automatically creates other Applications found within that folder. It’s "Applications all the way down."

## 📁 Directory Structure

```text
apps/
├── base/             # The "What": Raw Kubernetes manifests (Deployments, Services)
│   └── hello-world/  # Example application template
└── production/       # The "Where": ArgoCD Application manifests that point to base/
    └── hello-world.yaml # An Application manifest that tells ArgoCD to deploy hello-world
```

## 🛠️ How to Add a New Application

### Step 1: Define the Base (The Manifests)
Create a new folder in `apps/base/<app-name>/` and add your Kubernetes manifests (`deployment.yaml`, `service.yaml`, `ingress.yaml`). These should be generic enough to be reused.

### Step 2: Define the Application (The ArgoCD CRD)
Create a new YAML file in `apps/production/<app-name>.yaml`. This file tells ArgoCD where to find the code.

Example structure for a production app file:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-new-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/msavdert/homelab.git
    targetRevision: main
    path: apps/base/my-new-app
  destination:
    server: https://kubernetes.default.svc
    namespace: my-new-app-ns
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## 🚀 Getting Started

1. **Push your changes**: Ensure all files in `apps/` are committed and pushed to your GitHub `main` branch.
2. **Bootstrap**: In your `terraform/kubernetes` folder, set `install_argocd_app_of_apps = true` in `terraform.tfvars` and run `terraform apply`.
3. **Watch the magic**: Log into your ArgoCD UI and watch the applications automatically spin up!
