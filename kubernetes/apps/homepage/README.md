# Homepage Dashboard

A modern, highly customizable homelab dashboard that serves as the central landing page for our cluster services.

## Architecture

This application is deployed as a native Kubernetes application managed by ArgoCD via the App-of-Apps pattern.

### Components
- **Deployment**: Runs the `ghcr.io/gethomepage/homepage` container.
- **ConfigMaps**: Stores all YAML configurations (`services.yaml`, `bookmarks.yaml`, etc.).
- **RBAC**: ServiceAccount with a ClusterRole to allow Homepage to discover Kubernetes resources (Namespaces, Pods, Nodes) for its monitoring widgets.
- **Ingress**: Exposed via **Tailscale Ingress** for secure, zero-config access over the Tailnet.

## Access

The dashboard is accessible over Tailscale MagicDNS at:
`https://home.tail70417b.ts.net`

## Configuration

All configurations are managed via `configmaps.yaml`.

- `settings.yaml`: Global UI settings and themes.
- `bookmarks.yaml`: External links (GitHub, Proxmox, etc.).
- `services.yaml`: Internal cluster services.
- `widgets.yaml`: Status widgets (Time, Kubernetes status).
- `kubernetes.yaml`: Kubernetes cluster connection mode.

### Adding New Services
To add a new service to the dashboard:
1. Edit `configmaps.yaml`.
2. Add a new entry under `services.yaml`.
3. Commit and push the changes. ArgoCD will automatically update the ConfigMap and Homepage will hot-reload the settings.

## Troubleshooting

### API Error (Kubernetes Widget)
If you see an "API Error" in the Kubernetes widget, it is likely because `metrics-server` is not installed in the cluster. Homepage requires the Metrics API to display CPU and Memory usage.

### Host Validation Failed
Homepage has a security feature that validates the incoming `Host` header. Ensure that any domain used to access the dashboard is included in the `HOMEPAGE_ALLOWED_HOSTS` environment variable in `deployment.yaml`.

## References
- [Official Documentation](https://gethomepage.dev/)
- [Kubernetes Installation Guide](https://gethomepage.dev/installation/k8s/)
- [Tailscale Kubernetes Operator](https://tailscale.com/kb/1236/kubernetes-operator/)
