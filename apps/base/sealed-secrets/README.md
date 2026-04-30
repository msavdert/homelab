# Sealed Secrets (Bitnami)

Sealed Secrets provides a way to encrypt your Kubernetes Secrets into a "SealedSecret" which is safe to store even in a public repository. The SealSecret can be decrypted only by the controller running in the target cluster.

## How it works
1. **Controller:** Runs in the cluster (`kube-system` namespace) and holds the private key.
2. **CLI (`kubeseal`):** Runs on your local machine and uses the public key from the cluster to encrypt secrets.

## Installation
Managed via ArgoCD using the official Bitnami Helm chart.

## Usage
To seal a secret:
```bash
# 1. Create a normal secret locally (DO NOT COMMIT THIS)
kubectl create secret generic my-secret --from-literal=token=my-token --dry-run=client -o yaml > secret.yaml

# 2. Seal it using kubeseal
kubeseal --format=yaml < secret.yaml > sealed-secret.yaml

# 3. Commit sealed-secret.yaml to Git
# 4. Delete secret.yaml
```
