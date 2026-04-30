# Mastering Kubernetes Access: Cloudflare Tunnel & Cilium Ingress

This guide explains how to expose your internal Kubernetes services to the public internet securely using **Cloudflare Tunnel** and **Cilium Ingress Controller**. 

## 🏗️ Architecture Overview

The connection follows this secure path:
`User` -> `Cloudflare Edge` -> `Cloudflare Tunnel (Encrypted TCP)` -> `cloudflared pod` -> `Cilium Ingress Controller` -> `App Pod`

### Why this architecture?
1. **No Open Ports:** You don't need to open port 80/443 on your router. The tunnel creates an *outbound* connection to Cloudflare.
2. **Zero Trust Integration:** You can easily add 2FA, Email login, or device posture checks before anyone even touches your cluster.
3. **High Availability:** By running `cloudflared` as a Kubernetes Deployment with multiple replicas, the tunnel remains active even if one node fails.
4. **Cilium Power:** We use Cilium as the internal router (Ingress Controller), giving us eBPF-powered performance and security.

---

## 🛠️ Step 1: Create the Tunnel in Cloudflare

Before deploying the code, you must create the tunnel in the Cloudflare Dashboard:

1. Log in to [Cloudflare Zero Trust](https://one.dash.cloudflare.com).
2. Navigate to **Networks** > **Connectors** > **Tunnels**.
3. Select **Create a tunnel** > **Cloudflared**.
4. Name it (e.g., `homelab-k8s`) and Save.
5. Under **Choose an environment**, select **Docker**.
6. **Copy the Token:** Look for a long string starting with `eyJhIjoi...`. This is your `TUNNEL_TOKEN`.

---

## 🚀 Step 2: Deploy to Kubernetes

We follow the official recommended pattern: **Deployment + Secret**.

### 1. Configure the Token
Update the `secret.yaml` in this directory with your token. 
*(Note: In a production environment, you should use a Secret Manager like External Secrets Operator or Sealed Secrets).*

### 2. The Deployment
The `deployment.yaml` runs the `cloudflared` daemon. It is configured with:
- **Replicas: 2** (For High Availability).
- **Liveness Probe:** Checks the `/ready` endpoint to ensure the tunnel is connected.
- **ICMP Support:** Allows `ping` and `traceroute` through the tunnel.

---

## 🪄 Step 3: Wildcard Tunnel Setup (The "Magic" Trick)

Instead of creating a new tunnel route for every single app, we use a single entry point: **Cilium Ingress**. This allows total automation.

### 1. Cloudflare DNS Configuration
1. Go to your domain's **DNS Records** in Cloudflare.
2. Delete any existing `*` records if they point to other services (like Dokploy).
3. Create a new **CNAME** record:
   - **Name:** `*` (asterisk)
   - **Target:** `<your-tunnel-id>.cfargotunnel.com`
   - **Proxy Status:** Proxied (Orange Cloud)

### 2. Tunnel Hostname Configuration
In the Cloudflare Zero Trust Dashboard (**Networks > Tunnels**):
1. Select your tunnel and click **Edit**.
2. Go to the **Public Hostname** tab and add:
   - **Subdomain:** `*`
   - **Domain:** `savdert.com`
   - **Service:** `http://cilium-ingress.kube-system:80`
3. Under **HTTP Settings**, ensure `HTTP Host Header` is **empty** (Null).

### 3. Create an Ingress Resource
Now, for any app you want to expose, simply create an `Ingress` manifest in Kubernetes. 

**Example for `hello-world`:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-world
  annotations:
    ingress.cilium.io/loadbalancer-mode: shared
spec:
  ingressClassName: cilium
  rules:
  - host: hello.savdert.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: hello-world
            port:
              number: 80
```

### What happens next?
1. You go to `hello.savdert.com`.
2. Cloudflare matches the `*` wildcard and sends the request through the tunnel.
3. The request hits your `cloudflared` pod, which forwards it to `cilium-ingress`.
4. Cilium sees the `Host: hello.savdert.com` header and routes it to the `hello-world` pod.

**Result:** Total automation. No more manual Tunnel configuration in the dashboard!

---

## 🔒 Security Best Practices

1. **Access Policies:** Always create an "Access Application" in Zero Trust for sensitive UIs (ArgoCD, Grafana).
2. **Resource Limits:** Ensure your `cloudflared` pods have CPU/Memory limits to prevent them from consuming cluster resources.
3. **No-TLS Verify:** If your internal services use self-signed certs, configure the tunnel service with `No TLS Verify`.
