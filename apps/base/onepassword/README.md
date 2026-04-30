# 1Password Secrets Automation Guide

This guide explains how to integrate your 1Password account with this Kubernetes cluster.

## 🛠️ Step 1: Create the Automation in 1Password

1.  Log in to your **1Password** account via the web browser.
2.  Create a **new dedicated Vault** named `Homelab-K8s` (Recommended for security).
3.  Go to the [1Password Developer Dashboard](https://my.1password.com/integrations/directory/automation).
4.  Select **Connect Server** > **Create a Connect Server**.
5.  Name it `homelab-cluster`.
6.  **Important:** Select the `Homelab-K8s` vault you just created.
7.  Complete the setup and **download** the following two items:
    - `1password-credentials.json` (The credentials file).
    - `Access Token` (A long string starting with `eyJhbG...`).

---

## 🚀 Step 2: Create the Kubernetes Secret

Before the Operator can start, you must provide it with the credentials. Run the following command from your terminal (replacing the placeholders):

```bash
kubectl create namespace onepassword

# Create the secret from your downloaded file and token
kubectl create secret generic op-credentials \
  --namespace onepassword \
  --from-file=1password-credentials.json=/path/to/your/1password-credentials.json \
  --from-literal=token="YOUR_ACCESS_TOKEN_HERE"
```

---

## 🤖 Step 3: How to use it in GitOps

Once the operator is running, you can create a `OnePasswordItem` to sync a secret.

**Example:**
```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: cloudflare-token
  namespace: kube-system
spec:
  itemPath: "vaults/Homelab-K8s/items/Cloudflare-Token"
```

The operator will automatically find that item in 1Password and create a standard Kubernetes Secret named `cloudflare-token` in your cluster.
