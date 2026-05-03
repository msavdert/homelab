# VictoriaMetrics Helm Ecosystem: Confusion Buster

The VictoriaMetrics documentation can be overwhelming due to the large number of Helm charts. This document explains the architecture behind this modularity and why we chose our specific path.

## Why so many charts?
VictoriaMetrics follows a **"Modular First"** philosophy. Unlike some monolithic monitoring solutions, VM allows you to swap every single piece of the observability pipeline.

### 1. The Building Blocks (Component Charts)
These charts deploy individual components. You use these if you want to build a custom pipeline:
- **victoria-metrics-single**: Metrics storage (one pod).
- **victoria-metrics-cluster**: Metrics storage (distributed).
- **victoria-metrics-agent**: Only the scraper (vmagent).
- **victoria-metrics-alert**: Only the alerting engine (vmalert).
- **victoria-logs-single/cluster**: Only log storage.

### 2. The Management Layer
- **victoria-metrics-operator**: The core engine that manages the lifecycle of all the above. Instead of manually editing Deployments, you create "Custom Resources" (CRDs), and the operator does the work.

### 3. The "Easy Button" (Stack Charts)
- **victoria-metrics-k8s-stack**: This is the chart we are using. It is the equivalent of `kube-prometheus-stack`.
    - **It bundles**: Operator + Metrics + Grafana + Alerting + Default Dashboards + Default Rules.
    - **Why use it?** It's opinionated, pre-configured for Kubernetes, and provides the best "out-of-the-box" experience.

## Cluster vs. Distributed: What's the difference?
You might see `victoria-metrics-cluster` and `victoria-metrics-distributed`.
- **victoria-metrics-cluster**: Deploys a `VMCluster` resource. It **requires the Operator**. This is the modern way.
- **victoria-metrics-distributed**: Deploys `vmstorage`, `vminsert`, and `vmselect` as standard Kubernetes deployments. It **does NOT use the Operator**. This is used by people who prefer pure Helm over Operators.

## Specialized Components
- **MCP (Management & Configuration Protocol)**: Used for large-scale environments where you want to push configurations to thousands of `vmagent` instances from a central point.
- **Gateway**: A proxy for multi-tenancy and rate limiting.
- **Auth**: A simple auth proxy for security.

## Our Choice: The "Modular Stack" Approach
We are using the **K8s-Stack** for the core (Metrics/Grafana) but supplementing it with **VictoriaLogs** and **VictoriaTraces** as separate sources. This gives us:
1. The stability and pre-config of the official stack.
2. The cutting-edge features of Logs and Traces.
3. A clean GitOps structure in ArgoCD.
