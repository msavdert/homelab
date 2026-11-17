# 09 Homepage

## What this adds

A start page for the lab's applications at `https://home.lab.savdert.com`,
built with Homepage (gethomepage.dev). Only a user of Keycloak realm `lab`
can open it. Applications appear on it by themselves: Homepage reads
annotations on their `HTTPRoute`s.

```
namespace keycloak
  KeycloakRealmImport lab -> Job lab (once) -> realm lab in keycloak-db
    client homepage (confidential, standard flow), user owner

namespace homepage (pod security: restricted)
  homepage (Deployment, 1 pod, read-only root file system)
    <- HTTPRoute home.lab.savdert.com <- Gateway network/lab
    -> https://keycloak.lab.savdert.com/realms/lab  (OIDC login)
    -> Kubernetes API (read-only: namespaces, pods, nodes, HTTPRoutes, Gateways)
```

Homepage has its own login since version 2.0: with it on, every page and
API route needs a session, except `/api/healthcheck`. It signs in against
realm `lab`; realm `master` stays for administration. Why this and not an
Envoy Gateway `SecurityPolicy` or oauth2-proxy: D41 in
[Decisions](../decisions.md).

## Before you start

- [08 Keycloak](08-keycloak.md): Keycloak and its operator in `keycloak`.
- [05 Ingress](05-ingress.md): Gateway `lab` and the wildcard certificate.
- [04 Secrets](04-secrets.md): ClusterSecretStore `onepassword`.
- 1Password, vault `homelab-cluster`, created on 2026-11-17 with the
  `homelab` service account, values generated and never printed:
  - item `homepage`: `oidc-client-secret`, `auth-secret`;
  - item `keycloak-lab-user`: `username` (`owner`), `password`.

  A `SECURE_NOTE` holds the two Homepage fields; a `PASSWORD` item would
  require a field named `password`. For the login item, give the fields
  `purpose` `USERNAME` and `PASSWORD` in the template, or 1Password adds
  its own empty `username` and `password` next to yours.

## Steps

Flux applies the files when they are merged to `main`.

### 1. Realm `lab`

`kubernetes/apps/keycloak/realm-lab/`, Flux Kustomization
`keycloak-realm-lab` (after `keycloak` and `external-secrets-stores`):

- `externalsecrets.yaml`: Secret `realm-lab` with the client secret and
  the user's password.
- `realmimport.yaml`: a `KeycloakRealmImport` that creates realm `lab`,
  client `homepage` (redirect URI
  `https://home.lab.savdert.com/api/auth/callback/homepage-oidc`) and user
  `owner`. The two secrets are `placeholders`: the operator passes them to
  the import Job as environment variables and the realm file refers to
  them as `${HOMEPAGE_CLIENT_SECRET}` and `${OWNER_PASSWORD}`. The Flux
  Kustomization has no `postBuild`, so Flux leaves `${...}` alone.

The operator runs the import once, as Job `lab`, with `--override=false`:
an existing realm is skipped, and a later change to the resource does not
change the realm. Change the realm with `kcadm.sh` and write the change
back into the file. The Job sets `resources` (1 GiB request, 2 GiB limit,
as D40); it ran under pod security level `restricted` in about 105
seconds. Flux waits for the condition `Done`.

### 2. Homepage

`kubernetes/apps/homepage/`, Flux Kustomization `homepage` (after the
realm, the Gateway and the secret store). Plain manifests in the shape of
the upstream Kubernetes page; there is no official chart.

- `rbac.yaml`: ServiceAccount, and a ClusterRole with `get` and `list` on
  namespaces, pods, nodes, HTTPRoutes and Gateways. Upstream's rules for
  Traefik, Ingress and the metrics API are left out: the cluster has none
  of them. Upstream's long-lived token Secret is left out too; the pod
  uses its projected token, and the name `homepage` belongs to the next
  Secret.
- `externalsecrets.yaml`: Secret `homepage` with `auth-secret` and
  `oidc-client-secret`.
- `configmap.yaml`: the nine configuration files. `kubernetes.yaml` sets
  `mode: cluster`, `gateway: true`, `ingress: false`.
- `deployment.yaml`: image `ghcr.io/gethomepage/homepage:v2.8.0`, updated
  by Renovate's `kubernetes` manager. Login settings:
  `HOMEPAGE_AUTH_ENABLED`, `HOMEPAGE_AUTH_SECRET`, `HOMEPAGE_EXTERNAL_URL`,
  `HOMEPAGE_OIDC_ISSUER` (realm `lab`), `HOMEPAGE_OIDC_CLIENT_ID`,
  `HOMEPAGE_OIDC_CLIENT_SECRET`, `HOMEPAGE_OIDC_AUTO_LOGIN`.
  `HOMEPAGE_ALLOWED_HOSTS` lists the public name and the pod's own address
  for the probes.
- `service.yaml`, `httproute.yaml`: port 3000, `home.lab.savdert.com`.

**Read-only root file system.** When `/api/validate` runs (the page calls
it after login), Homepage copies every file of `/app/src/skeleton` that is
missing from `/app/config`, and the process exits when it cannot. So all
nine skeleton files are mounted from the ConfigMap, even empty ones;
`/app/config/logs` and `/app/.next/cache` are `emptyDir` volumes. The first
version mounted eight; see "When it goes wrong".

### 3. Put an application on the page

Annotate its `HTTPRoute`, as `kubernetes/apps/keycloak/keycloak/app/httproute.yaml`
does:

```yaml
metadata:
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: Keycloak
    gethomepage.dev/group: Identity
    gethomepage.dev/icon: keycloak.png
    gethomepage.dev/description: Identity provider
    gethomepage.dev/href: https://keycloak.lab.savdert.com
    gethomepage.dev/pod-selector: app.kubernetes.io/instance=keycloak,app.kubernetes.io/component=server
```

`pod-selector` gives the entry its status: Homepage shows the state of the
matching pods ("running" in green).

## Check

The gate of phase 9, run on 2026-11-17 after the merges of pull requests
42 and 43.

1. Without a session the page is closed:

   ```
   $ curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' https://home.lab.savdert.com/
   307 https://home.lab.savdert.com/auth/signin?callbackUrl=%2F
   ```

2. The issuer of realm `lab`:

   ```
   $ curl -s https://keycloak.lab.savdert.com/realms/lab/.well-known/openid-configuration | jq -r .issuer
   https://keycloak.lab.savdert.com/realms/lab
   ```

   From inside the Homepage pod the same request returns the same issuer,
   so the pod reaches Keycloak through the Gateway and trusts its
   certificate:

   ```
   $ kubectl -n homepage exec deploy/homepage -- node -e 'fetch("https://keycloak.lab.savdert.com/realms/lab/.well-known/openid-configuration").then(r=>r.json()).then(j=>console.log("from pod:",j.issuer))'
   from pod: https://keycloak.lab.savdert.com/realms/lab
   ```

3. From the owner's device: the sign-in went to Keycloak realm `lab`, the
   login from item `keycloak-lab-user` was accepted, and the page showed
   Keycloak in group "Identity" with the status "running" in green. The
   pod had no restarts afterwards.

4. Delete the pod; the new one was ready in 13 seconds, and the page
   opened again on the owner's device without any manual step:

   ```
   $ kubectl -n homepage delete pod -l app.kubernetes.io/name=homepage --wait=true
   pod "homepage-766c977cb9-fwx2g" deleted from homepage namespace
   $ kubectl -n homepage get pods --no-headers
   homepage-766c977cb9-wkv2c   1/1   Running   0     13s
   ```

5. Pod security:

   ```
   $ kubectl get ns homepage --show-labels
   ... pod-security.kubernetes.io/enforce=restricted ...
   ```

   The import Job of step 1 ran in `keycloak`, which is `restricted` too:
   `Done=True`, Job `lab` `Complete 1/1`.

## Day-two tasks

- **Upgrade.** Renovate proposes the image tag. Before merging, list
  `/app/src/skeleton` in the new image (`docker run --rm --entrypoint ls
  ghcr.io/gethomepage/homepage:<tag> /app/src/skeleton`); every file there
  needs an entry in the ConfigMap and a mount, or the pod crashes after
  login.
- **Change the page.** Edit `configmap.yaml`. A ConfigMap mounted by
  `subPath` is not updated in a running pod: after Flux applies it,
  `kubectl -n homepage rollout restart deploy/homepage`.
- **Who can log in.** Everyone with a login in realm `lab`; Homepage
  checks no claims. Add or remove users there (admin console, realm
  `lab`, or `kcadm.sh -r lab`).
- **The user's password.** Item `keycloak-lab-user` was used only for the
  first import. Changing it later changes nothing in Keycloak; change the
  password in Keycloak and then in the item.
- **Rotate the client secret.** Regenerate it in Keycloak (client
  `homepage`, Credentials), put the new value in item `homepage` field
  `oidc-client-secret`, wait for the ExternalSecret to refresh, then
  restart the Deployment. Not tested here.

## When it goes wrong

- **The page works, then "upstream connect error or disconnect/reset
  before headers".** Seen on 2026-11-17 with the first version: the pod
  restarted on every page load after login. `kubectl -n homepage logs
  deploy/homepage --previous` showed `EROFS: read-only file system,
  copyfile '/app/src/skeleton/proxmox.yaml' -> '/app/config/proxmox.yaml'`.
  A skeleton file was not mounted. Reproduced with Docker on the box: the
  same image with `--read-only` and eight files exits on `GET
  /api/validate`; with all nine it answers 200. Fixed in pull request 43.
- **Flux `homepage` waits for `keycloak-realm-lab`.** Check the import:
  `kubectl -n keycloak get keycloakrealmimport lab -o
  jsonpath='{.status.conditions}'` and the logs of Job `lab`.

## Sources

- Homepage installation, Kubernetes: the manifests, the ClusterRole, the
  `HOMEPAGE_ALLOWED_HOSTS` example. https://gethomepage.dev/installation/k8s/
- Homepage installation, "Security / Authentication": the variables, the
  callback path, the routes that stay open. https://gethomepage.dev/installation/
- Homepage Kubernetes configuration: `gateway: true` and the
  `gethomepage.dev/*` annotations. https://gethomepage.dev/configs/kubernetes/
- Homepage releases: v2.8.0. https://github.com/gethomepage/homepage/releases
- The v2.8.0 image itself: `/app/src/skeleton` (nine files), the server
  code of `/api/validate`.
- Keycloak Operator realm import: create only, `placeholders`.
  https://www.keycloak.org/operator/realm-import
- `keycloak/keycloak` at tag 26.8.2:
  `KeycloakRealmImportJobDependentResource.java` (the Job, `--override=false`)
  and `KeycloakRealmImportStatusCondition.java` (`Done`, `HasErrors`).
