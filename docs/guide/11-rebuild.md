# 11 Rebuild and restore

## What this adds

A tested way back from nothing: the three nodes are destroyed and the
cluster is rebuilt from Git and the bucket alone, with both PostgreSQL
clusters restored from their archives (D45). Run on 2026-11-17; the whole
rebuild took 20 minutes from `tofu apply` to the last Ready Kustomization.

```
bucket homelab
  cnpg/postgres/        generation 1, read by the recovery, then left alone
  cnpg/postgres-g2/     generation 2, written by the rebuilt cluster
  cnpg/keycloak-db/     generation 1
  cnpg/keycloak-db-g2/  generation 2
```

Each Cluster carries `bootstrap.recovery` from an `externalClusters` entry
`previous` (the last generation) and archives under the next generation in
`spec.plugins[].parameters.serverName`. Bootstrap runs only when a Cluster
is created.

## Before you start

- The owner's go-ahead: the drill destroys VMs 201 to 203.
- The recovery change is not merged yet. A running cluster refuses a second
  bootstrap method, so merged early, Flux's apply fails:
  `spec.bootstrap: Forbidden: Only one bootstrap method can be specified at
  a time`.
- Both clusters healthy, `ContinuousArchiving` True.

## Steps

### 1. Markers and a last backup

A row and a Keycloak user that exist only if the data really came back:

```
$ kubectl -n database exec postgres-1 -c postgres -- psql -d app \
    -c "create table drill_marker (note text, at timestamptz default now())" \
    -c "insert into drill_marker(note) values ('phase 11 marker 2026-11-17')" \
    -c "alter table drill_marker owner to app"
```

and `$K create users -r lab -s username=drill-marker -s enabled=true`
through `kcadm.sh` (Keycloak guide, check step 3). Then a backup of each
cluster:

```
$ kubectl cnpg backup -n database postgres --method plugin \
    --plugin-name barman-cloud.cloudnative-pg.io --backup-name postgres-predrill
$ kubectl cnpg backup -n keycloak keycloak-db --method plugin \
    --plugin-name barman-cloud.cloudnative-pg.io --backup-name keycloak-db-predrill
$ kubectl get backup -A | grep predrill
database   postgres-predrill      ...   completed
keycloak   keycloak-db-predrill   ...   completed
```

List the bucket and keep the listing (see "Look at the bucket"). Before
the drill it held `postgres/` (10 base, 11 WAL objects) and `keycloak-db/`
(8 base, 143 WAL objects) only.

### 2. Destroy (14 s)

```
$ cd infra
$ export OP_SERVICE_ACCOUNT_TOKEN="$(op read op://dotfiles/homelab-op-service-account/credential)"
$ op run --env-file op.env -- tofu plan -destroy -out=destroy.plan
  # proxmox_virtual_environment_vm.node["k8s-1"] will be destroyed
  # proxmox_virtual_environment_vm.node["k8s-2"] will be destroyed
  # proxmox_virtual_environment_vm.node["k8s-3"] will be destroyed
Plan: 0 to add, 0 to change, 3 to destroy.
$ op run --env-file op.env -- tofu apply destroy.plan
Apply complete! Resources: 0 added, 0 changed, 3 destroyed.
```

Read the plan: nothing outside the three nodes may appear. Then merge the
recovery pull request (here #56, generation 2).

### 3. Rebuild

The same tasks as the Cluster guide, "Rebuild the cluster from nothing".
Times from the drill (UTC):

| Step | Command | Took |
|---|---|---|
| VMs | `tofu plan -out create.plan`, `tofu apply create.plan` (or `mise run infra:apply`, which asks) | 49 s |
| Maintenance mode | Talos API on port 50000 | at once |
| Machine config | `mise run talos:apply k8s-N --insecure`, N = 1 to 3 | 10 s |
| Install and reboot | `mise run talos:config`, wait for stage `booting` | 9 s |
| etcd | `mise run talos:bootstrap`; API on 10.0.6.10:6443 | 23 s |
| Kubeconfig | `mise run talos:kubeconfig`; three nodes NotReady | 53 s |
| Cilium | `mise run bootstrap:cilium`; nodes Ready | 60 s |
| Token | `mise run bootstrap:secrets` | 4 s |
| Flux | `mise run bootstrap:flux`, ends when `cilium` and `flux-operator` are adopted | 1 min 39 s |
| Everything else | `flux get kustomizations -A --watch` until 21/21 Ready | 14 min 18 s |

The last step is mostly the database recoveries and what waits for them:
`postgres` was healthy with three instances 6 minutes after Flux, then
`keycloak-db`, Keycloak, realm `lab` and Homepage; the monitoring stack
came last. The Talos version installed is the one in the installer image
of `talos/patches/cluster.yaml` (v1.14.6, the same as the disk image this
time; with a newer installer image the node would boot the disk image's
version into maintenance mode first, which is still an assumption).

## Check

Nodes and Flux:

```
$ kubectl get nodes
k8s-1   Ready   v1.36.6
k8s-2   Ready   v1.36.6
k8s-3   Ready   v1.36.6
$ kubectl get ks -A    # 21 of 21 Ready
$ kubectl get hr -A    # 10 of 10 Ready
```

Flux adopted Cilium without a restart (D33): the three Cilium pods kept
the creation time of `bootstrap:cilium` (14:35:39) with 0 restarts.

The databases:

```
$ kubectl -n database get cluster postgres -o jsonpath=...
postgres: Cluster in healthy state; archiving=True; ready=3/3; server=postgres-g2
keycloak-db: Cluster in healthy state; archiving=True; ready=2/2; server=keycloak-db-g2
$ kubectl get backup -A
database   postgres-daily-20261117144024      postgres      completed
keycloak   keycloak-db-daily-20261117144258   keycloak-db   completed
```

All five instances are Burstable. The data came back:

```
$ kubectl -n database exec postgres-1 -c postgres -- psql -d app -tc 'select note, at from drill_marker'
 phase 11 marker 2026-11-17 | 2026-11-17 13:35:53.377744+00
```

The recovered timeline is 4. In Keycloak the import job found the realm
and left it alone:

```
INFO  [org.keycloak.exportimport.util.ImportUtils] (main) Realm 'lab' already exists. Import skipped
```

and `kcadm.sh get users -r lab -q username=drill-marker` returns the user
with its original ID (`2cd6206c-...`); clients `grafana` and `homepage` are
there. Keycloak connected with the regenerated `keycloak-db-app` Secret,
so the recovered role's password matches it (inferred from the working
connection; the operator log was not read).

The bucket after the rebuild:

```
      2 keycloak-db-g2/base
     10 keycloak-db-g2/wals
      8 keycloak-db/base
    143 keycloak-db/wals
      2 postgres-g2/base
     12 postgres-g2/wals
     10 postgres/base
     11 postgres/wals
```

The listing of the old prefixes is identical to the one from step 1, object
for object.

With `bootstrap.recovery` still in Git, `flux reconcile ks postgres` and
`keycloak` apply cleanly and stay Ready.

## Day-two tasks

- **The next rebuild.** One pull request: `externalClusters[].plugin.
  parameters.serverName` to the last generation (`postgres-g2`), the
  archive `serverName` to the next (`postgres-g3`), the same for
  `keycloak-db`. Merge it after the destroy, never before.
- **Old generations.** The plugin is assumed not to prune them (the old
  prefixes were unchanged after the rebuild; the 6b run on generation 2
  will show it for retention). Keep the previous
  generation as a restore point; delete older prefixes by hand with the
  owner's approval once the current one has a completed base backup.
- **Retention.** Follow-up 6b of phase 7 is repeated on generation 2: with
  `retentionPolicy: 1d`, a day after the rebuild the plugin should remove
  the first `-g2` backup once a newer one completes. Then retention goes
  back to `7d`.

## When it goes wrong

- **`spec.bootstrap: Forbidden: Only one bootstrap method`.** The recovery
  change met a running cluster. Revert it, or finish the destroy first.
- **`Expected empty archive`, cluster stays in `Setting up primary`.** The
  archive `serverName` points at a prefix that holds WAL. Move it to the
  next generation; do not use `cnpg.io/skipEmptyWalArchiveCheck`.
- **The recovery job cannot reach the bucket.** It needs the same
  `AWS_ENDPOINT_URL_S3` as the instances; the plugin gives the
  `instanceSidecarConfiguration` of the ObjectStore to the `full-recovery`
  job too (seen on the job's `plugin-barman-cloud` container).

## Look at the bucket

The bucket key of the cluster is in Secret `object-storage`; the values go
into the environment of one command and are never printed:

```
g(){ kubectl -n database get secret object-storage -o jsonpath="{.data.$1}" | base64 -d; }
AWS_ACCESS_KEY_ID="$(g access-key)" AWS_SECRET_ACCESS_KEY="$(g secret-key)" \
  AWS_DEFAULT_REGION="$(g region)" AWS_REQUEST_CHECKSUM_CALCULATION=when_required \
  AWS_RESPONSE_CHECKSUM_VALIDATION=when_required \
  aws --endpoint-url "$(g endpoint)" s3 ls --recursive s3://homelab/cnpg/
```

## Sources

- CloudNativePG, Recovery (the empty-archive check, unique `serverName`).
- Barman Cloud plugin, Usage (recovery through `externalClusters[].plugin`;
  `spec.plugins` enables archiving).
- Keycloak, "Deploy CloudNativePG recovery" (a new `serverName` for the
  recovered cluster).
- D45, and the review of 2026-11-17 (V1, V10, V11, V18).
