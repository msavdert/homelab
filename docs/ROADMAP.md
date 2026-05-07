# Homelab Modernization Roadmap

Goal: Build a modern, simple, well-documented, and easy-to-manage homelab on Proxmox & Talos Linux.

## Phase 0: Foundation (Level 0) - COMPLETED
- [x] Hetzner Dedicated Server setup.
- [x] Proxmox VE installation via QEMU Rescue.
- [x] SDN (Software-Defined Networking) configuration.
- [x] Tailscale for secure management.

## Phase 1: Infrastructure as Code (Level 1) - IN PROGRESS
- [ ] Refine Terraform for Talos Cluster.
  - [x] Dynamic ISO URL from Talos Factory.
  - [ ] Add Control Plane health checks.
  - [ ] Implement `talhelper` (Optional but recommended for scaling).
- [ ] Deploy Control Plane and Workers.
- [ ] Verify node connectivity and Talos API access.

## Phase 2: Bootstrap & Basic Networking (Level 2)
- [ ] Basic Cilium installation (via Terraform `inlineManifests`).
- [ ] Verify nodes reach `Ready` state.
- [ ] Configure `local-path-provisioner` (temporary) or wait for Longhorn.
- [ ] Deploy ArgoCD.

## Phase 3: GitOps Migration (Level 3)
- [ ] Create `homelab-ops` repository for GitOps.
- [ ] Move Cilium management to ArgoCD (Helm Chart).
- [ ] Deploy Longhorn for persistent storage.
- [ ] Deploy External-DNS and Cert-Manager.
- [ ] Implement Ingress/Gateway API via Cilium.

## Phase 4: Observability & Security
- [ ] Prometheus & Grafana (via kube-prometheus-stack).
- [ ] Loki/Tempo for logs and traces.
- [ ] Renovate for automated dependency updates.
- [ ] 1Password integration for secret management.

---

## Strategy: Keep it Simple

1. **Avoid Over-engineering**: Start with the minimal set of tools. Use Cilium for as much as possible (CNI, LoadBalancer, Ingress, Gateway API, Network Policies).
2. **Standardize Documentation**: Every service must have a `CLAUDE.md` or `README.md` explaining its purpose and how to troubleshoot.
3. **Automate Everything**: If it's not in Git, it doesn't exist.
4. **Talos First**: Treat nodes as immutable cattle. No manual SSH, no manual config changes.
