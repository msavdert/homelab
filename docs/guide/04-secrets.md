# 04 Secrets

## What this adds

A Secret in the cluster can come from 1Password. External Secrets Operator
2.15.0 reads vault `homelab-cluster` through the 1Password SDK provider,
with a service account that can only read that vault (D11, D25). An
`ExternalSecret` names an item and a field; the operator writes the value
into a Kubernetes Secret and refreshes it every hour. No secret value is
in Git; the one token the operator needs is applied once by a bootstrap
task.

## Before you start

- [03 Flux](03-flux.md): Flux reconciles `kubernetes/apps/` from `main`.
- In 1Password (done by the owner on 2026-11-15):
  - vault `homelab-cluster` with item `cloudflare-dns`;
  - a service account that can read only `homelab-cluster`;
  - its token in vault `homelab`, item `eso-service-account`, field
    `credential`;
  - item `cloudflare-dns` also in vault `homelab`, for the workstation's
    own tasks.
- `op` signed in with the box's service account, which can read
  `op://dotfiles/homelab-op-service-account/credential` (the read-write
  token of vault `homelab`).
- Network access to `ghcr.io` (the chart and images) and to 1Password from
  the nodes.

How the read-only account was checked, with its token in
`OP_SERVICE_ACCOUNT_TOKEN`:

```
op vault list                                   # only homelab-cluster
op read op://homelab/cloudflare-dns/credential  # refused: no access to vault homelab
op item create --vault homelab-cluster --category "Secure Note" --title ro-write-test
# [ERROR] (101) You do not have permission to perform this action
```

## Steps

### 1. The layout

```
kubernetes/apps/external-secrets/
  kustomization.yaml            # namespace.yaml and the ks.yaml below
  namespace.yaml                # never pruned: it holds the token Secret
  external-secrets/
    ks.yaml                     # two Flux Kustomizations
    app/                        # the operator: OCIRepository, HelmRelease
    stores/                     # ClusterSecretStore
bootstrap/external-secrets/
  secret.yaml                   # the token Secret, as an op inject template
```

The operator and its CRDs come from the chart in `app/`. The store in
`stores/` is an object of those CRDs (since phase 5 the ExternalSecrets
live with their applications), so they get their
own Flux Kustomization, `external-secrets-stores`, which `dependsOn` the
operator's. The operator's Kustomization has `wait: true`, so it is Ready
only when the HelmRelease is; the stores are applied after that.

### 2. The operator

`app/ocirepository.yaml` pins chart `2.15.0` from
`oci://ghcr.io/external-secrets/charts/external-secrets`;
`app/helmrelease.yaml` uses it with the chart defaults: one replica each
of the controller, the webhook and the certificate controller. The chart
ships its CRDs as templates (`installCRDs: true` by default), so a chart
upgrade upgrades the CRDs too. The pods run as non-root with all
capabilities dropped and pass the baseline Pod Security level Talos
enforces, so the namespace needs no label.

### 3. The store

`stores/onepassword.yaml`:

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: onepassword
spec:
  provider:
    onepasswordSDK:
      vault: homelab-cluster
      auth:
        serviceAccountSecretRef:
          name: onepassword-service-account
          namespace: external-secrets
          key: token
```

A `ClusterSecretStore` can be used from every namespace. That is safe
here only because the vault behind it holds nothing but what workloads
are meant to have (D25). `kubectl get clustersecretstore` shows
`CAPABILITIES ReadWrite`: that is what the provider supports, not what
the account may do. The account was refused a write (above).

The stores Kustomization reports Ready only when the store has the
condition `Ready=True` (`healthCheckExprs` in `ks.yaml`). A store that cannot log in keeps the Kustomization in
progress until its five-minute timeout, then it fails and retries every
two minutes.

### 4. The token

```
mise run bootstrap:secrets
```

The task reads the read-write token of vault `homelab` from `dotfiles`,
creates namespace `external-secrets` if it is missing, and pipes
`op inject -i bootstrap/external-secrets/secret.yaml` into
`kubectl apply`. The template holds only the reference
`{{ op://homelab/eso-service-account/credential }}`; the value goes
through the pipe and never touches a file or a command line. It needs
only the API server, so on a rebuild it runs between `bootstrap:cilium`
and `bootstrap:flux` ([Cluster](02-cluster.md), "Day-two tasks"). Without it,
`bootstrap:flux` waits for the store until it times out.

The token Secret is not in Git and not in Flux's inventory, so Flux never
changes or prunes it. The namespace carries
`kustomize.toolkit.fluxcd.io/prune: disabled` for the same reason.

### 5. The gate secret

`stores/eso-gate.yaml` copied field `credential` of item `cloudflare-dns`
into Secret `eso-gate` in namespace `external-secrets`. The key is
`<item>/<field>`. It existed only to prove the path and was removed in
phase 5, when cert-manager got its own ExternalSecret for the same item
(`kubernetes/apps/cert-manager/cert-manager/issuers/cloudflare-dns.yaml`).
The check below shows it as it was.

## Check

Run on 2026-11-15. `mise run bootstrap:secrets` was run before the merge
(namespace and Secret `serverside-applied`; the token's length matched the
1Password item). Pull request #18 was merged at 17:27:29 UTC; after a
`flux reconcile kustomization flux-system --with-source`, both new
Kustomizations were Ready within three minutes and `eso-gate` synced at
17:30:21.

```
$ flux get kustomizations -A
NAMESPACE    NAME                     REVISION                       READY  MESSAGE
flux-system  cilium                   refs/heads/main@sha1:84a84f40  True   Applied revision: refs/heads/main@sha1:84a84f40
flux-system  external-secrets         refs/heads/main@sha1:84a84f40  True   Applied revision: refs/heads/main@sha1:84a84f40
flux-system  external-secrets-stores  refs/heads/main@sha1:84a84f40  True   Applied revision: refs/heads/main@sha1:84a84f40
flux-system  flux-instance            refs/heads/main@sha1:84a84f40  True   Applied revision: refs/heads/main@sha1:84a84f40
flux-system  flux-operator            refs/heads/main@sha1:84a84f40  True   Applied revision: refs/heads/main@sha1:84a84f40
flux-system  flux-system              refs/heads/main@sha1:84a84f40  True   Applied revision: refs/heads/main@sha1:84a84f40
$ kubectl get clustersecretstore
NAME          AGE   STATUS   CAPABILITIES   READY
onepassword   24s   Valid    ReadWrite      True
$ kubectl -n external-secrets get externalsecret eso-gate
NAME       STORETYPE            STORE         REFRESH INTERVAL   STATUS         READY   LAST SYNC
eso-gate   ClusterSecretStore   onepassword   1h                 SecretSynced   True    12s
$ kubectl -n external-secrets get secret eso-gate -o jsonpath='{.data.credential}' | base64 -d | sha256sum
e233062bccf2b3916f8556647fe91d12039623fcf9b7c7b26ec0cae11f5c3710  -
$ OP_SERVICE_ACCOUNT_TOKEN="$(op read op://dotfiles/homelab-op-service-account/credential)" op read op://homelab/cloudflare-dns/credential | tr -d '\n' | sha256sum
e233062bccf2b3916f8556647fe91d12039623fcf9b7c7b26ec0cae11f5c3710  -
```

(`SUSPENDED` column trimmed.) The two hashes are equal: the value in the
cluster is the value in 1Password, and it was never printed.

## Day-two tasks

- **Add a secret.**
  1. Put the item in vault `homelab-cluster`, and only there if the
     workstation does not need it. Anything in this vault can be read by
     any namespace that can create an ExternalSecret.
  2. Next to the application that uses it, add an ExternalSecret:

     ```yaml
     apiVersion: external-secrets.io/v1
     kind: ExternalSecret
     metadata:
       name: <app>
     spec:
       refreshInterval: 1h
       secretStoreRef:
         kind: ClusterSecretStore
         name: onepassword
       target:
         name: <app>
       data:
         - secretKey: <key in the Secret>
           remoteRef:
             key: <item>/<field>
     ```

     For every field of an item at once, use
     `dataFrom: [{extract: {key: <item>}}]` instead of `data`.
  3. Merge. `kubectl -n <ns> get externalsecret <app>` shows
     `SecretSynced`. A changed value in 1Password reaches the cluster
     within `refreshInterval`; `kubectl annotate externalsecret <app>
     force-sync=$(date +%s) --overwrite` fetches it at once.
  If the application's Kustomization applies before External Secrets is
  ready on a new cluster, it retries; add `dependsOn:
  external-secrets-stores` to its `ks.yaml` if it must not start without
  the Secret.
- **Rotate the read-only token.** Rotate it in 1Password, write the new
  token to `op://homelab/eso-service-account/credential`, run
  `mise run bootstrap:secrets`. The store picks the new Secret up on its
  next check; `kubectl get clustersecretstore` shows `Valid`.
- **Upgrade the operator.** Renovate proposes the chart tag in
  `app/ocirepository.yaml`; the CRDs move with the chart.
- **Remove the operator.** Deleting the HelmRelease deletes the CRDs,
  because they are chart templates without a keep policy, and with them
  every ExternalSecret and the Secrets they own. It is a deliberate step,
  not a cleanup.

## When it goes wrong

- **The store is not Ready, message about authentication.** The token
  Secret is missing or old. `kubectl -n external-secrets get secret
  onepassword-service-account` must exist; run `mise run
  bootstrap:secrets` again.
- **An ExternalSecret reports `SecretSyncedError`.** The item or field
  name is wrong, or the item is not in `homelab-cluster`. `kubectl
  describe externalsecret <name>` shows the provider's message. Item and
  field names are matched as written; duplicate field labels in one item
  are an error.
- **A token was printed.** During this phase a gate run with `set -x`
  printed the read-write token of vault `homelab` into a session log; the
  owner rotated it the same day. Show gate commands by writing them out,
  never by tracing a shell that expands `$(op read ...)`.

## Sources

- External Secrets documentation:
  [1Password SDK provider](https://external-secrets.io/latest/provider/1password-sdk/)
  (`onepasswordSDK.vault`, `auth.serviceAccountSecretRef`, the
  `<item>/[section/]<field>` key form, `dataFrom.extract`, duplicate
  labels) and
  [stability and support](https://external-secrets.io/latest/introduction/stability-support/)
  (2.15 supports Kubernetes 1.37).
- The 2.15.0 chart, pulled and rendered: CRDs as templates, `installCRDs`
  true, `external-secrets.io/v1` served and stored, `v1beta1` not served,
  the pod security settings. The
  [release](https://github.com/external-secrets/external-secrets/releases/latest)
  and the [OCI package](https://github.com/external-secrets/external-secrets/pkgs/container/charts%2Fexternal-secrets).
- Flux `fluxcd/pkg` `runtime/cel` (how `healthCheckExprs` are evaluated:
  in progress, failed, current; a missing field is Unknown) and
  `kubectl explain kustomization.spec.healthCheckExprs` (only `current`
  is required).
- [buroa/home-ops](https://github.com/buroa/home-ops):
  `kubernetes/apps/external-secrets/external-secrets/` (the `app/` and
  `stores/` split with `dependsOn`, the ClusterSecretStore, CEL health
  checks) and `bootstrap/.../secret.yaml` (the token as an `op://`
  template). Not taken: the ExternalSecret that refreshes the token from
  the same vault (here the token lives in vault `homelab`, which the
  cluster cannot read), the metrics and dashboard values, two webhook
  replicas.
