# 📘 Tailscale Operator: Integration Guide & Troubleshooting

This document provides a comprehensive guide on how the Tailscale Kubernetes Operator is integrated into our Talos/Cilium cluster, how to expose internal applications securely, how to access the Kubernetes API server directly via Tailscale, and detailed troubleshooting steps for known issues.

---

## 🚀 1. Exposing New Web Applications (Step-by-Step)

To expose a new web interface (e.g., Grafana, Prometheus) to your Tailnet securely using MagicDNS and Let's Encrypt, follow these steps:

### Step 1.1: Ensure the Backend Supports HTTP
Tailscale proxy terminates TLS (HTTPS) at the proxy pod and forwards the traffic to your application over **HTTP (Port 80)**. 
- If your application serves HTTPS by default (like ArgoCD), you **must** configure it to run in insecure/HTTP mode.
- For example, ArgoCD requires the `server.insecure: "true"` flag in its `argocd-cmd-params-cm` ConfigMap.

### Step 1.2: Create the Tailscale Ingress Resource
Create an `Ingress` resource in the same namespace as your application. You must specify:
1. `ingressClassName: tailscale`
2. An annotation for the MagicDNS hostname: `tailscale.com/hostname: "your-app-name"`
3. The `tls` block with the same hostname.

**Example Ingress:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-tailscale-ingress
  namespace: observability
  annotations:
    tailscale.com/hostname: "grafana"
spec:
  ingressClassName: tailscale
  tls:
    - hosts:
        - "grafana"
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana-service # Must match your app's service name
                port:
                  number: 80          # Must be the HTTP port of the service
```

### Step 1.3: Access the Application
1. Apply the manifest (via GitOps/ArgoCD).
2. Open your browser and navigate **strictly** using the HTTPS MagicDNS URL: 
   `https://grafana.<your-tailnet-name>.ts.net`
3. *Note: Do not use the IP address directly or `http://`, as Tailscale relies on SNI (Server Name Indication) to fetch the Let's Encrypt certificate on-the-fly.*

---

## ☸️ 2. Accessing the Kubernetes API Server via Tailscale

The Tailscale Operator can act as an API Server Proxy. This allows you to run `kubectl` commands from anywhere in the world on your Tailscale network without exposing your Talos API server to the public internet. Furthermore, Tailscale handles authentication and passes your Tailscale Identity to Kubernetes via impersonation!

### Step 2.1: Enable API Server Proxy in Helm Values
In your `kubernetes/core/tailscale/values.yaml` (or wherever your Tailscale Helm values are managed), enable the API Server Proxy:

```yaml
apiServerProxyConfig:
  mode: "true"
```

Commit and push this change to let ArgoCD sync it. The Tailscale Operator will now advertise itself as a Kubernetes API endpoint on your Tailnet.

### Step 2.2: Configure RBAC for your Tailscale Identity
When `auth` mode is true, Tailscale passes your Tailscale email (e.g., `alice@example.com`) as the Kubernetes user. You must grant this user permissions in Kubernetes.

Create a `ClusterRoleBinding`:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tailscale-cluster-admins
subjects:
- kind: User
  name: "your-email@gmail.com" # Replace with your Tailscale login email
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
```

### Step 2.3: Connect from your Local Machine
From your local Macbook (or any machine connected to your Tailnet), run the following command to automatically generate a `kubeconfig` pointing to the Tailscale Operator:

```bash
tailscale configure kubeconfig
```
You can now run `kubectl get pods -A` securely over Tailscale!

---

## 🛠️ 3. Troubleshooting Post-Mortem: Cilium & MagicDNS

When initially setting up the Tailscale Operator with Cilium (in `kube-proxy` replacement mode) and ArgoCD, we encountered several architectural conflicts. Here is how they were diagnosed and resolved.

### Issue A: Cilium Socket LoadBalancer Bypass (Connection Reset)
- **Symptom:** The Tailscale Ingress proxy was successfully deployed, but attempting to reach the backend ArgoCD pods resulted in "Connection Reset" or timeouts.
- **Root Cause:** Talos + Cilium `kubeProxyReplacement` relies on **eBPF Socket LoadBalancing**. This feature optimizes traffic by bypassing the Pod's virtual ethernet (`veth`) interface entirely, routing traffic directly at the TCP socket layer. However, Tailscale relies on `netfilter` rules attached to the `veth` interface to encrypt and route traffic into the Tailnet. Because traffic bypassed `veth`, Tailscale could not capture it.
- **Resolution:** We modified `kubernetes/core/cilium/values.yaml` to restrict the Socket LB to the host namespace only. This forces pod-to-service traffic through `veth`.
  ```yaml
  socketLB:
    hostNamespaceOnly: true
  ```

### Issue B: The "No Certificate Found" & SNI Error
- **Symptom:** Accessing the Tailscale proxy IP directly (`https://100.x.x.x`) resulted in TLS handshake errors (`no SNI ServerName`). In the Tailscale Admin Console, the machine showed `TLS Certificate Status: No certificate found`.
- **Root Cause:** 
  1. Let's Encrypt certificates are provisioned by Tailscale **lazily** (on-the-fly) when the very first valid TLS ClientHello arrives containing the correct Server Name Indication (SNI) matching the MagicDNS hostname.
  2. Because the user attempted to access the service via IP instead of the MagicDNS URL, the SNI was missing. Tailscale rejected the connection and never procured the certificate.
- **Resolution:** The user must **only** access the service using the fully qualified domain name (e.g., `https://argocd.tail70417b.ts.net`). Bypassing DNS will always fail.

### Issue C: Local MacOS DNS overriding MagicDNS
- **Symptom:** Running `ping argocd.tail70417b.ts.net` from the local Macbook resulted in `Unknown host`.
- **Root Cause:** The user's Tailscale client on MacOS was not intercepting DNS queries. This occurs when "Use Tailscale DNS settings" is disabled in the macOS Tailscale Menu Bar App, or if an aggressive Global DNS (like `1.1.1.1` or `8.8.8.8`) is hardcoded in macOS Wi-Fi settings, overriding the Tailscale internal resolver (`100.100.100.100`).
- **Resolution:** 
  1. Open the Tailscale app on macOS -> Preferences -> Check **"Use Tailscale DNS settings"**.
  2. Remove hardcoded DNS servers from macOS Network settings to allow Tailscale to intercept `.ts.net` queries.

---
**References:**
- [Tailscale Kubernetes Operator CNI Compatibility](https://tailscale.com/docs/features/kubernetes-operator#cni-compatibility)
- [Cilium Socket LoadBalancer Bypass](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/#socket-loadbalancer-bypass-in-pod-namespace)
- [Tailscale API Server Proxy](https://tailscale.com/docs/features/kubernetes-operator/how-to/api-server-proxy)
