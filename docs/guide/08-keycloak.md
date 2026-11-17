# 08 Keycloak

## What this adds

Keycloak, an identity provider (a service that logs users in and issues
OIDC and SAML tokens to applications), at
`https://keycloak.lab.savdert.com`. It is the lab's first application.
It will give the owner's applications one login, and later it will be
the place to practise LDAP, Active Directory and Kerberos integration
for databases. Keycloak is not a directory server itself; that comes in
a later phase. Why Keycloak and not authentik, ZITADEL or the others:
D38 in [Decisions](../decisions.md).

```
namespace keycloak (pod security: restricted)
  keycloak-operator (Deployment)   watches this namespace only
  keycloak-0 (StatefulSet, 1 pod)  built by the operator from Keycloak/keycloak
    <- HTTPRoute keycloak.lab.savdert.com <- Gateway network/lab (TLS ends here)
    -> keycloak-db-rw:5432
  keycloak-db-1, keycloak-db-2 (CloudNativePG, one per node)
    -> s3://homelab/cnpg/keycloak-db/{base,wals}/
```

Keycloak keeps all of its state (realms, users, clients, sessions) in
PostgreSQL. The database is its own CloudNativePG cluster, not a
database inside cluster `postgres`: a restore or a major upgrade acts on
a whole cluster, and `postgres` is the drill target (D39). Because the
database is backed up, Keycloak needs no volume backup; D16 stands.

## Before you start

- [07 Database](07-database.md): the CloudNativePG operator and the Barman
  Cloud Plugin in `cnpg-system`, and the `object-storage` item in vault
  `homelab-cluster`.
- [05 Ingress](05-ingress.md): Gateway `lab` in `network`, the wildcard
  certificate and the DNS record `*.lab.savdert.com`.
- [04 Secrets](04-secrets.md): ClusterSecretStore `onepassword`.
- 1Password: item `keycloak` in vault `homelab-cluster` with the fields
  `username` and `password`. It was created on 2026-11-16 with the
  `homelab` service account (the cluster's own account can only read):

```
$ OP_SERVICE_ACCOUNT_TOKEN="$(op read op://dotfiles/homelab-op-service-account/credential)" \
    op item create --vault homelab-cluster --category login --title keycloak \
    --generate-password='32,letters,digits' username=admin --format json \
    | jq -r '.title, .vault.name'
keycloak
homelab-cluster
```

## Steps

All files are under `kubernetes/apps/keycloak/`. Flux applies them when
they are merged to `main`.

### 1. Namespace

`namespace.yaml` creates `keycloak` with
`pod-security.kubernetes.io/enforce: restricted`. Neither the operator's
manifests nor the Keycloak pod the operator builds set a
`securityContext` (operator 26.8.2), so steps 2 and 4 add one. Both
images run as user 1000 (`USER 1000` in `operator/Dockerfile` and
`quarkus/container/Dockerfile` at tag 26.8.2), which is what
`runAsNonRoot` needs.

### 2. The operator

`keycloak-operator/ks.yaml` holds two Flux objects:

- a `GitRepository` on `https://github.com/keycloak/keycloak-k8s-resources`
  at tag `26.8.2`, ignoring everything except `kubernetes/` and skipping
  `kubernetes/cluster-wide` (that variant is a preview);
- a `Kustomization` with `path: ./kubernetes`. The upstream
  `kustomization.yml` there already sets namespace `keycloak` and points
  the binding subjects at it.

Two strategic-merge patches in the Flux `Kustomization`:

- every `CustomResourceDefinition` gets
  `kustomize.toolkit.fluxcd.io/prune: disabled`. The operator's
  installation page warns that deleting the CRDs deletes every Keycloak
  resource, so Flux must never remove them, even if this directory is
  deleted;
- Deployment `keycloak-operator` gets `runAsNonRoot`, seccomp
  `RuntimeDefault`, no privilege escalation and all capabilities dropped.

The tag pins both the operator and Keycloak: the operator starts
Keycloak with the image in its `RELATED_IMAGE_KEYCLOAK` variable,
`quay.io/keycloak/keycloak:26.8.2`. Result after merge:

```
$ kubectl -n flux-system get gitrepository keycloak-operator
NAME                URL                                                  AGE   READY   STATUS
keycloak-operator   https://github.com/keycloak/keycloak-k8s-resources   19m   True    stored artifact for revision '26.8.2@sha1:79ba77fd...'
```

### 3. Database cluster and backups

In `keycloak/app/`, following D39 and the files of cluster `postgres`:

- `externalsecrets.yaml`: Secret `object-storage` from the item of the
  same name, because Secrets do not cross namespaces;
- `objectstore.yaml`: destination `s3://homelab/cnpg/`; the plugin
  appends the cluster name, so backups land in `cnpg/keycloak-db/`. The
  checksum variables and the endpoint from the Secret are the same as in
  [07 Database](07-database.md). Retention is `1d` like `postgres` until
  the phase 7 follow-up is closed (D37);
- `cluster.yaml`: `keycloak-db`, two instances, required anti-affinity
  per node, 5Gi each, image `18.6-minimal-trixie`;
- `scheduledbackup.yaml`: daily at 03:30 UTC, `immediate: true`.

CloudNativePG creates the database `app`, owned by user `app`, and the
Secret `keycloak-db-app` with keys `username` and `password` among
others.

### 4. Keycloak

`externalsecrets.yaml` also creates Secret `keycloak-admin` from item
`keycloak`. `keycloak.yaml` is the `Keycloak` resource (API
`k8s.keycloak.org/v2beta1`, field names checked against the CRD at
26.8.2):

| Field | Value | Why |
|---|---|---|
| `instances` | 1 | one pod is enough for a lab |
| `db` | `postgres`, host `keycloak-db-rw`, database `app`, user and password from `keycloak-db-app` | the CloudNativePG primary |
| `bootstrapAdmin.user.secret` | `keycloak-admin` | the first admin, keys `username` and `password` |
| `http.httpEnabled` | `true` | Envoy ends TLS and forwards plain HTTP |
| `hostname.hostname` | `https://keycloak.lab.savdert.com` | Keycloak builds its URLs from this name |
| `proxy.headers` | `xforwarded` | trust Envoy's `X-Forwarded-*` headers |
| `ingress.enabled` | `false` | the operator would create an Ingress; the lab uses Gateway API |
| `resources` | memory request 1Gi, limit 2Gi | D40 |
| `unsupported.podTemplate` | pod and container `securityContext` | the restricted level |

The operator uses `unsupported.podTemplate` as the base of the
StatefulSet and edits only the first container's name, image, ports and
environment (`KeycloakDeploymentDependentResource.java` at 26.8.2), so the
security settings survive. `spec.networkPolicy` is left at its default:
the operator creates `keycloak-network-policy`, which admits HTTP from any
source and limits the clustering port 7800 to Keycloak's own pods.

### 5. Route

`httproute.yaml` sends `keycloak.lab.savdert.com` to `keycloak-service`
port 8080. The management port 9000 (health and metrics) on the same
Service is not routed.

```
$ kubectl -n keycloak get svc keycloak-service
NAME               TYPE        CLUSTER-IP      PORT(S)
keycloak-service   ClusterIP   10.105.148.28   8080/TCP,9000/TCP
```

### 6. Ordering

`keycloak/ks.yaml` depends on `external-secrets-stores`,
`local-path-provisioner`, `plugin-barman-cloud`, `keycloak-operator` and
`envoy-gateway-gateway` (the HTTPRoute CRD and the Gateway). It is Ready
only when both ExternalSecrets, `keycloak-db` and `Keycloak` report
Ready. The first apply took about five minutes from merge:

```
$ kubectl -n flux-system get kustomization keycloak-operator keycloak
NAME                READY   STATUS
keycloak-operator   True    Applied revision: 26.8.2@sha1:79ba77fd...
keycloak            True    Applied revision: refs/heads/main@sha1:cbb25562...
$ kubectl -n keycloak get pods
NAME                                 READY   STATUS    RESTARTS   AGE
keycloak-0                           1/1     Running   0          73s
keycloak-db-1                        2/2     Running   0          3m9s
keycloak-db-2                        2/2     Running   0          2m26s
keycloak-operator-575df7b788-9bxmr   1/1     Running   0          5m1s
```

## Check

Run on 2026-11-17 (UTC), with `main` at `cbb2556`; step 2 from the owner's
laptop and from the agent box.

**1. Database and backup.**

```
$ kubectl cnpg status keycloak-db -n keycloak
...
Status:                  Cluster in healthy state
Instances:               2
Ready instances:         2
...
Continuous Backup status (Barman Cloud Plugin)
ObjectStore / Server name:      object-storage/keycloak-db
Last Successful Backup:         2026-11-16 22:00:27 EST
Working WAL archiving:          OK
...
Name           Current LSN  Replication role  Status  QoS         Manager Version  Node
keycloak-db-1  0/725F110    Primary           OK      BestEffort  1.30.1           k8s-3
keycloak-db-2  0/725F110    Standby (async)   OK      BestEffort  1.30.1           k8s-1
```

A read-only listing of the bucket, with the workstation's key from vault
`homelab` (sizes in bytes):

```
$ aws s3 ls --recursive --endpoint-url "$EP" s3://homelab/cnpg/keycloak-db/
1435     base/20261117T025954/backup.info
4118734  base/20261117T025954/data.tar.gz
2619253  wals/0000000100000000/000000010000000000000001.gz
...
321692   wals/0000000100000000/000000010000000000000006.gz
```

**2. Over the tailnet.** The issuer shows that Keycloak builds its URLs
from the public name behind Envoy (the roadmap's "Prove here"):

```
$ curl -s https://keycloak.lab.savdert.com/realms/master/.well-known/openid-configuration | jq -r .issuer
https://keycloak.lab.savdert.com/realms/master
$ curl -s -o /dev/null -w 'HTTP %{http_code}, TLS verify=%{ssl_verify_result}\n' \
    https://keycloak.lab.savdert.com/admin/master/console/
HTTP 200, TLS verify=0
```

The owner logged in to the admin console from macOS with the credentials
of item `keycloak`. The console shows a banner: "You are logged in as a
temporary admin user." See "Day-two tasks".

**3. Data survives the pod.** `kcadm.sh` runs inside the pod and reads
the admin credentials from the pod's own environment
(`KC_BOOTSTRAP_ADMIN_USERNAME`, `KC_BOOTSTRAP_ADMIN_PASSWORD`, set by the
operator from `keycloak-admin`), so no secret passes through the
workstation. A script piped into the pod logs in:

```
K=/opt/keycloak/bin/kcadm.sh
export HOME=/tmp
$K config credentials --server http://localhost:8080 --realm master \
  --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD"
```

```
$ { cat login.sh; echo '$K create realms -s realm=gate -s enabled=true && $K create users -r gate -s username=gate-user -s enabled=true'; } \
    | kubectl -n keycloak exec -i keycloak-0 -- sh
Created new realm with id 'gate'
Created new user with id '1ac3b481-01c8-4ce6-a988-3e1f7c9d1983'
$ kubectl -n keycloak get pod keycloak-0 -o jsonpath='{.metadata.uid}'
dfc4959d-3cfa-464e-a225-e6ac8630615d
$ kubectl -n keycloak delete pod keycloak-0
$ kubectl -n keycloak wait pod/keycloak-0 --for=condition=Ready --timeout=300s
pod/keycloak-0 condition met
$ kubectl -n keycloak get pod keycloak-0 -o jsonpath='{.metadata.uid}'
8b1b3e6d-1e73-41de-8ddf-979677548300
$ { cat login.sh; echo '$K get realms/gate --fields realm,enabled; $K get users -r gate -q username=gate-user --fields id,username'; } \
    | kubectl -n keycloak exec -i keycloak-0 -- sh
{
  "realm" : "gate",
  "enabled" : true
}
[ {
  "id" : "1ac3b481-01c8-4ce6-a988-3e1f7c9d1983",
  "username" : "gate-user"
} ]
```

Realm `gate` is left in place as evidence; it has no clients.

**4. Pod security.** Re-labelling the namespace as a server-side dry run
makes the API server evaluate the running pods; it printed no warning.

```
$ kubectl get ns keycloak --show-labels
NAME       STATUS   AGE   LABELS
keycloak   Active   ...   ...,pod-security.kubernetes.io/enforce=restricted
$ kubectl -n keycloak get pods -o custom-columns=POD:.metadata.name,RUNASNONROOT:.spec.securityContext.runAsNonRoot,SECCOMP:.spec.securityContext.seccompProfile.type
POD                                  RUNASNONROOT   SECCOMP
keycloak-0                           true           RuntimeDefault
keycloak-db-1                        true           RuntimeDefault
keycloak-db-2                        true           RuntimeDefault
keycloak-operator-575df7b788-9bxmr   true           RuntimeDefault
$ kubectl label --dry-run=server --overwrite ns keycloak pod-security.kubernetes.io/enforce=restricted
namespace/keycloak not labeled (server dry run)
```

**Memory (D40).** The cluster has no metrics API; the kubelet's summary
gives the working set. After the change to 1Gi requested:

```
$ kubectl get --raw /api/v1/nodes/k8s-3/proxy/stats/summary | jq '.pods[] | select(.podRef.name=="keycloak-0") | .memory.workingSetBytes'
478355456
$ kubectl -n keycloak get sts keycloak -o jsonpath='{.spec.template.spec.containers[0].resources}'
{"limits":{"memory":"2Gi"},"requests":{"memory":"1Gi"}}
```

That is 456 MiB two minutes after the pod restarted with the new request.
Before the change the reads were 564 MiB a few minutes after a restart
and 536 MiB about seven minutes after start.

## Day-two tasks

- **Log in as admin.** The admin console is
  `https://keycloak.lab.savdert.com/admin/`; the credentials are item
  `keycloak` in vault `homelab-cluster`.
- **The temporary admin.** Keycloak 26 marks the bootstrap admin as
  temporary and asks for a permanent one. It is kept for now: removing it
  needs a permanent admin and a service account for automation, and both
  belong with the decision on how realms are kept in Git, which is made
  when the first client is added. `KeycloakRealmImport` only creates
  realms and never updates them.
- **Run `kcadm.sh`.** As in check step 3: pipe the login lines and the
  command into `kubectl -n keycloak exec -i keycloak-0 -- sh`.
- **Upgrade.** Renovate bumps the `GitRepository` tag; minor and major
  bumps are labelled `upgrade-drill`. The tag moves the operator and
  Keycloak together because the `Keycloak` resource has no `spec.image`.
  Read the release notes first: 26.8 changed the database schema, and a
  schema change cannot be undone by going back a version. Take a manual
  `Backup` of `keycloak-db` before merging. Whether Renovate's flux
  manager picks up a `GitRepository` tag has not been seen yet.
- **Never delete the CRDs.** Removing `keycloaks.k8s.keycloak.org`
  removes every `Keycloak` resource and with it the StatefulSet; the data
  stays in `keycloak-db`. Flux does not prune them (step 2); a manual
  `kubectl delete -k` of the upstream directory would.
- **Change the admin password** in the console or with `kcadm.sh`.
  Changing item `keycloak` alone updates Secret `keycloak-admin` but not
  the user in the database, because the bootstrap admin is created only
  once. Not tested here.
- **Restart Keycloak.** `kubectl -n keycloak delete pod keycloak-0`; the
  StatefulSet recreates it in about a minute.
- **Database tasks** (backup now, restore, switch primary): as in
  [07 Database](07-database.md), with `keycloak-db` in namespace
  `keycloak`.

## When it goes wrong

Nothing failed while building this layer.

## Sources

- Keycloak Operator documentation: installation (kustomize at a tag,
  single-namespace watch, "deleting the CRDs deletes all Keycloak CRs"),
  basic deployment (`db`, `hostname`, `proxy`, `ingress`), advanced
  configuration (`bootstrapAdmin`, `resources`, `unsupported.podTemplate`,
  default 1700MiB request and 2GiB limit), realm import (create only).
  https://www.keycloak.org/operator/installation
- `keycloak/keycloak-k8s-resources` at tag 26.8.2: `kubernetes/kustomization.yml`
  (namespace `keycloak`, binding subjects), `kubernetes/kubernetes.yml`
  (operator Deployment, no securityContext, `RELATED_IMAGE_KEYCLOAK`), the
  four CRDs (v2beta1 schema).
- `keycloak/keycloak` at tag 26.8.2: `operator/.../KeycloakDeploymentDependentResource.java`
  (pod template as the base, first container renamed `keycloak`),
  `Constants.java` (ports and Service suffix), `KeycloakNetworkPolicyDependentResource.java`,
  `operator/Dockerfile` and `quarkus/container/Dockerfile` (`USER 1000`).
- Keycloak memory and CPU sizing: heap at 70% of the container limit,
  about 300 MB outside the heap, 1250 MB base per pod with 10,000 sessions.
  https://www.keycloak.org/high-availability/single-cluster/concepts-memory-and-cpu-sizing
- Flux kustomize-controller: `spec.patches`, the prune annotation,
  `healthCheckExprs`. https://fluxcd.io/flux/components/kustomize/kustomizations/
- Renovate flux manager: `GitRepository` with a `tag`, datasource
  `github-tags`. https://docs.renovatebot.com/modules/manager/flux/
- CloudNativePG FAQ (one cluster per database), the basis of D39.
