# 07 Database

!!! note "Follow-up 6b closed on 2026-11-19"
    The gate passed on 2026-11-16. Step 6b, the plugin's own retention
    removing an expired backup (D37), was observed on archive generation
    2 on 2026-11-19 (output under step 6 of the check); retention is back
    to 7 days.

## What this adds

A three-instance PostgreSQL cluster, `postgres` in namespace `database`,
run by CloudNativePG. It archives every WAL segment and takes a daily base
backup to the bucket, so it can be restored to any point in time. This
page is also the drill: restore to a point in time, fail over by draining
a node, and remove old backups.

```
Cluster postgres (3 instances, one per node, local-path volumes of 10Gi)
  primary  --streaming replication-->  2 replicas
  every instance pod: postgres + plugin-barman-cloud sidecar
    sidecar on the primary: WAL archive (each segment), base backups,
                            retention run every 30 minutes
      -> s3://homelab/cnpg/postgres/{base,wals}/   (Oracle, path style)
Services: postgres-rw (primary), postgres-ro (replicas), postgres-r (any)
```

The operator and the Barman Cloud Plugin run in `cnpg-system`; the plugin
injects the sidecar and owns the `ObjectStore` resource that says where
backups go. Why this design and these versions: D15, D24, D27 and D36 in
[Decisions](../decisions.md).

## Before you start

- [06 Storage](06-storage.md): the default StorageClass `local-path`.
- [04 Secrets](04-secrets.md): ClusterSecretStore `onepassword`. Item
  `object-storage` in vault `homelab-cluster` with the fields
  `access-key`, `secret-key`, `endpoint`, `region` (a key that reaches only
  bucket `homelab`).
- cert-manager from [05 Ingress](05-ingress.md): the plugin's chart issues
  its own certificates.
- `kubectl cnpg` from `mise.toml` (`mise install`); every command below
  runs in the repository, where mise sets `KUBECONFIG`.

## Steps

### 1. Operator and plugin

`kubernetes/apps/cnpg-system/` installs two charts from
`oci://ghcr.io/cloudnative-pg/charts/` with their default values:
`cloudnative-pg` (the operator, its webhooks and CRDs) and
`plugin-barman-cloud`. The plugin must run in the operator's namespace and
needs operator 1.30 or newer, so the two are upgraded together. Its Flux
Kustomization depends on `cert-manager` and `cloudnative-pg`.

```
$ kubectl get ks -n flux-system cloudnative-pg plugin-barman-cloud
NAME                  AGE     READY   STATUS
cloudnative-pg        4m47s   True    Applied revision: refs/heads/main@sha1:adf2a8e...
plugin-barman-cloud   4m47s   True    Applied revision: refs/heads/main@sha1:adf2a8e...
```

### 2. Credentials and object store

`kubernetes/apps/database/postgres/app/` holds four files, applied by the
Flux Kustomization `postgres`.

- `externalsecret.yaml` copies the four fields of `object-storage` into
  Secret `object-storage`.
- `objectstore.yaml` points at `s3://homelab/cnpg/` with path-style
  addressing. The cluster name is appended, so this cluster writes to
  `cnpg/postgres/`. The endpoint is not in the file: it contains the
  tenancy namespace and the repository is public. It reaches the sidecar
  as the environment variable `AWS_ENDPOINT_URL_S3` from the Secret, which
  boto3 reads when `endpointURL` is unset. The two checksum variables are
  set to `when_required`, as the plugin documents for S3-compatible
  stores.
- The sidecar reads its environment only when an instance pod is created
  (plugin issue #918). After changing `instanceSidecarConfiguration`, run
  `kubectl cnpg restart postgres -n database`. `retentionPolicy` is
  different: the sidecar reads it from the API on every retention run.

### 3. Cluster and scheduled backup

- `cluster.yaml`: three instances, required pod anti-affinity on
  `kubernetes.io/hostname`, 10Gi each, image
  `ghcr.io/cloudnative-pg/postgresql:18.6-minimal-trixie`, and the plugin
  as WAL archiver. The `minimal` image is enough because Barman runs in
  the sidecar, not in the PostgreSQL image. `backup.target: primary`
  makes every backup run on the primary: one taken on an idle replica
  ends in a WAL segment that is never archived (D48).
- `scheduledbackup.yaml`: `"0 0 3 * * *"` (six fields, the first is
  seconds) is daily at 03:00 UTC; `immediate: true` takes the first backup
  at once.
- Namespace `database` enforces the `restricted` pod security level. The
  instance pods and the injected sidecar run under it without changes.

About five minutes after the merge:

```
$ kubectl cnpg status postgres -n database
Status:                  Cluster in healthy state
Instances:               3
Ready instances:         3
Continuous Backup status (Barman Cloud Plugin)
No recovery window information found in ObjectStore 'object-storage' for server 'postgres'
Working WAL archiving:        OK
WALs waiting to be archived:  0
...
Name        Current LSN  Replication role  Status  QoS         Manager Version  Node
postgres-1  0/8030918    Primary           OK      BestEffort  1.30.1           k8s-3
postgres-2  0/8030918    Standby (async)   OK      BestEffort  1.30.1           k8s-2
postgres-3  0/8030918    Standby (async)   OK      BestEffort  1.30.1           k8s-1

$ kubectl get backups -n database
NAME                            AGE     CLUSTER    METHOD   PHASE       ERROR
postgres-daily-20261116042322   3m20s   postgres   plugin   completed
```

"No recovery window information" appeared before the first backup was
recorded in the ObjectStore status; it is not an error.

### 4. Deleting backups on this bucket

The bucket refuses a multi-object delete unless it carries a checksum that
boto3 in the sidecar cannot send (D24, D36). The test runs Barman's own
delete command with the sidecar image, the same arguments the sidecar
uses (they appear in its log as `options`) and the same environment. It
needs two base backups; take the second by hand:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: postgres-manual-1
  namespace: database
spec:
  method: plugin
  cluster:
    name: postgres
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
```

Then a Job that lists, deletes the older backup and lists again (replace
the backup ID with the older one from the first list):

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: barman-delete-test
  namespace: database
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        seccompProfile: {type: RuntimeDefault}
      initContainers:
        - name: list-before
          image: ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:v0.16.0
          command: ["/venv/bin/barman-cloud-backup-list", "--cloud-provider", "aws-s3",
                    "--addressing-style", "path", "s3://homelab/cnpg/", "postgres"]
          env: &env
            - {name: AWS_ACCESS_KEY_ID, valueFrom: {secretKeyRef: {name: object-storage, key: access-key}}}
            - {name: AWS_SECRET_ACCESS_KEY, valueFrom: {secretKeyRef: {name: object-storage, key: secret-key}}}
            - {name: AWS_DEFAULT_REGION, valueFrom: {secretKeyRef: {name: object-storage, key: region}}}
            - {name: AWS_ENDPOINT_URL_S3, valueFrom: {secretKeyRef: {name: object-storage, key: endpoint}}}
            - {name: AWS_REQUEST_CHECKSUM_CALCULATION, value: when_required}
            - {name: AWS_RESPONSE_CHECKSUM_VALIDATION, value: when_required}
          securityContext: &sc
            allowPrivilegeEscalation: false
            capabilities: {drop: ["ALL"]}
        - name: delete
          image: ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:v0.16.0
          command: ["/venv/bin/barman-cloud-backup-delete", "-v", "--cloud-provider", "aws-s3",
                    "--addressing-style", "path", "-b", "20261116T042424",
                    "s3://homelab/cnpg/", "postgres"]
          env: *env
          securityContext: *sc
      containers:
        - name: list-after
          image: ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:v0.16.0
          command: ["/venv/bin/barman-cloud-backup-list", "--cloud-provider", "aws-s3",
                    "--addressing-style", "path", "s3://homelab/cnpg/", "postgres"]
          env: *env
          securityContext: *sc
```

```
$ kubectl logs -n database job/barman-delete-test -c list-before
Backup ID           End Time                 Begin Wal                     ...
20261116T042424     2026-11-16 04:24:32      000000010000000000000003
20261116T042838     2026-11-16 04:28:47      000000010000000000000007
$ kubectl logs -n database job/barman-delete-test -c delete
INFO: Found file from backup '20261116T042424' of server 'postgres': cnpg/postgres/base/20261116T042424/data.tar.gz
WARNING: Bulk delete failed with 'MissingContentMD5'. Falling back to deleting this file individually: cnpg/postgres/base/20261116T042424/data.tar.gz.
WARNING: Bulk delete failed with 'MissingContentMD5'. Falling back to deleting this file individually: cnpg/postgres/wals/0000000100000000/000000010000000000000001.gz.
... (the same for WAL 2 to 6)
$ kubectl logs -n database job/barman-delete-test -c list-after
Backup ID           End Time                 Begin Wal                     ...
20261116T042838     2026-11-16 04:28:47      000000010000000000000007
```

The bucket refuses the bulk delete, and Barman 3.20.1 falls back to one
request per object, which the bucket accepts. A direct listing of
`cnpg/` (boto3 `list_objects_v2` from the same image) confirmed it: only
the remaining backup and WAL from segment 7 on were left. So retention
can work without the fallback of D24. Gate step 6a repeats this with a
retention policy instead of a backup ID; step 6b shows whether the
plugin's own runs do it (D37).

The Backup object of a backup deleted this way stays in the cluster, and
`kubectl cnpg status` keeps showing it as the first point of
recoverability until the next retention run removes the object.

## Check

Run on 2026-11-16, UTC, after pull request #30 was merged.

**1. Status.** As in step 3 above: three instances, WAL archiving OK, a
completed base backup.

**2. Two rows around a target time.** On the primary, a row, the time,
a second row, then a WAL switch so the segment with both rows is archived:

```
$ kubectl exec -n database postgres-1 -c postgres -- psql -X -At \
    -c "create table drill(id int, note text, at timestamptz default clock_timestamp());" \
    -c "insert into drill(id,note) values (1,'before target');"
$ kubectl exec -n database postgres-1 -c postgres -- psql -X -At \
    -c "select to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')"
2026-11-16T04:32:03.376127Z
$ kubectl exec -n database postgres-1 -c postgres -- psql -X -At \
    -c "insert into drill(id,note) values (2,'after target');" \
    -c "select id,note,at from drill order by id;" \
    -c "select pg_walfile_name(pg_current_wal_lsn()), pg_switch_wal();"
1|before target|2026-11-16 04:31:59.989106+00
2|after target|2026-11-16 04:32:06.762928+00
000000010000000000000009|0/902D6E8
$ kubectl cnpg status postgres -n database | grep "Last Archived WAL"
Last Archived WAL:              000000010000000000000009   @   2026-11-16T04:32:08.53267Z
```

Wait for that line before restoring: a segment that is not archived yet
cannot be replayed.

**3. Restore to the target time.** A second cluster bootstrapped from the
object store. It has no `plugins` section, so it does not archive and
cannot write into the source's `cnpg/postgres/`:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-restore
  namespace: database
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:18.6-minimal-trixie
  storage:
    size: 2Gi
  bootstrap:
    recovery:
      source: origin
      recoveryTarget:
        targetTime: "2026-11-16T04:32:03.376127Z"
  externalClusters:
    - name: origin
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: object-storage
          serverName: postgres
```

```
$ kubectl apply -f restore.yaml
$ kubectl wait -n database cluster/postgres-restore --for=condition=Ready --timeout=600s
cluster.postgresql.cnpg.io/postgres-restore condition met
```

**4. The restored cluster has the first row only.**

```
$ kubectl exec -n database postgres-restore-1 -c postgres -- psql -X -At \
    -c "select id,note,at from drill order by id;" \
    -c "select pg_is_in_recovery(), timeline_id from pg_control_checkpoint();"
1|before target|2026-11-16 04:31:59.989106+00
f|2
```

The first row was written after the base backup (04:28:47), so it came
from WAL replay; replay stopped before the second. The restored cluster
was promoted to timeline 2. Delete it before the drain
(`kubectl delete -n database cluster/postgres-restore`): a one-instance
cluster's PodDisruptionBudget blocks draining its node.

**5. Drain the primary's node.** A probe pod on another node queries
`postgres-rw` once a second as user `app`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: rw-probe
  namespace: database
spec:
  nodeSelector:
    kubernetes.io/hostname: k8s-1
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 26
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: probe
      image: ghcr.io/cloudnative-pg/postgresql:18.6-minimal-trixie
      command: ["bash", "-c", "while true; do r=$(psql -X -At -h postgres-rw -U app -d app -c 'select inet_server_addr()' 2>&1 | head -1); echo \"$(date -u +%H:%M:%S) $r\"; sleep 1; done"]
      env:
        - {name: PGPASSWORD, valueFrom: {secretKeyRef: {name: postgres-app, key: password}}}
        - {name: PGCONNECT_TIMEOUT, value: "2"}
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: {drop: ["ALL"]}
```

```
$ kubectl drain k8s-3 --ignore-daemonsets --delete-emptydir-data --timeout=300s
node/k8s-3 cordoned
...
node/k8s-3 drained
$ kubectl logs -n database rw-probe
04:34:03 10.244.1.40
04:34:04 psql: error: connection to server at "postgres-rw" (10.105.103.140), port 5432 failed: No route to host
...
04:34:15 psql: error: connection to server at "postgres-rw" (10.105.103.140), port 5432 failed: No route to host
04:34:16 10.244.0.144
$ kubectl cnpg status postgres -n database | grep -E "Primary instance|^Status:"
Primary instance:        postgres-2
Status:                  Cluster in healthy state
$ kubectl uncordon k8s-3
$ kubectl cnpg status postgres -n database
...
Ready instances:         3
Working WAL archiving:          OK
```

The cordon alone started the switchover: the operator moved the primary
to `postgres-2` on k8s-2. `postgres-rw` failed for about 12 seconds
(04:34:04 to 04:34:15) and then answered from the new primary. After the
uncordon, `postgres-1` came back on k8s-3 as a replica.

**6. Retention.** Split in two (D37). Retention was `1d` until 6b had
been observed (pull request #31); it is `7d` since 2026-11-19.

*6a, retention delete on the bucket (2026-11-16).* The plugin cannot
expire a backup sooner than a day, so the same Barman command it runs is
run by hand with a policy that applies at once, as `DELETE OBSOLETE` with
`REDUNDANCY 2` would in RMAN. First three more backups, with WAL written
and switched before the last one so that it starts in a later segment
than the one before it (on an idle database two backups in a row start in
the same segment, and deleting the older would remove no WAL):

```
$ kubectl create -f backup.yaml        # postgres-manual-2, then -3
$ kubectl exec -n database postgres-2 -c postgres -- psql -X -At \
    -c "create table retention_probe(at timestamptz)" \
    -c "insert into retention_probe values (now())" \
    -c "checkpoint" -c "select pg_switch_wal()"
$ kubectl create -f backup.yaml        # postgres-manual-4
```

`backup.yaml` is a `Backup` with `method: plugin`, cluster `postgres` and
`pluginConfiguration.name: barman-cloud.cloudnative-pg.io`. Then the Job
from step 4, with its `delete` container replaced by two:

```yaml
        - name: dry-run
          image: ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:v0.16.0
          command: ["/venv/bin/barman-cloud-backup-delete", "-v", "--cloud-provider", "aws-s3",
                    "--addressing-style", "path", "-r", "REDUNDANCY 2", "--dry-run",
                    "s3://homelab/cnpg/", "postgres"]
          env: *env
          securityContext: *sc
        - name: delete
          image: ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:v0.16.0
          command: ["/venv/bin/barman-cloud-backup-delete", "-v", "--cloud-provider", "aws-s3",
                    "--addressing-style", "path", "-r", "REDUNDANCY 2",
                    "s3://homelab/cnpg/", "postgres"]
          env: *env
          securityContext: *sc
```

```
== list-before
Backup ID           End Time                 Begin Wal
20261116T042838     2026-11-16 04:28:47      000000010000000000000007
20261116T184847     2026-11-16 18:48:52      00000002000000000000000C
20261116T184904     2026-11-16 18:49:09      00000002000000000000000C
20261116T184933     2026-11-16 18:49:40      00000002000000000000000D
== delete
INFO: Found file from backup '20261116T042838' of server 'postgres': cnpg/postgres/base/20261116T042838/data.tar.gz
WARNING: Bulk delete failed with 'MissingContentMD5'. ... cnpg/postgres/base/20261116T042838/data.tar.gz.
INFO: Found file from backup '20261116T184847' of server 'postgres': cnpg/postgres/base/20261116T184847/data.tar.gz
... (one WARNING and single delete per object: the two data.tar.gz and
     backup.info files, WAL 1/7 to 1/B with the .backup and .partial
     files, and WAL 2/B)
== list-after
Backup ID           End Time                 Begin Wal
20261116T184904     2026-11-16 18:49:09      00000002000000000000000C
20261116T184933     2026-11-16 18:49:40      00000002000000000000000D
```

The dry run listed the same objects first. A direct listing of
`cnpg/postgres/` (boto3 `list_objects_v2` in a Job from the same image)
showed only what the two kept backups need:

```
cnpg/postgres/base/20261116T184904/backup.info
cnpg/postgres/base/20261116T184904/data.tar.gz
cnpg/postgres/base/20261116T184933/backup.info
cnpg/postgres/base/20261116T184933/data.tar.gz
cnpg/postgres/wals/00000002.history.gz
cnpg/postgres/wals/0000000200000000/00000002000000000000000C.gz
cnpg/postgres/wals/0000000200000000/00000002000000000000000D.gz
```

The table `retention_probe` was dropped afterwards.

*6b, the plugin's own run (follow-up, closed 2026-11-19).* The plan on
generation 1: with `1d`, backup
`20261116T184904` becomes obsolete when `20261116T184933` ended more than
a day ago, on 2026-11-17 after 18:49:40 UTC; the next 30-minute retention
run on the primary was to remove it and WAL segment 2/C. Check the
sidecar log, the bucket listing and `kubectl get backup -n database`
(only `postgres-manual-3` should go: plugin issue #1115 deletes Backup
objects on a short catalog listing).

The phase 11 rebuild moved both clusters to archive generation 2 before
that run was due, so 6b was observed there instead, on 2026-11-19. As
observed (the Barman documentation was not read for it), a recovery
window keeps the newest backup that ended before the window starts: the
first `-g2` backups of 2026-11-17 went only once the 2026-11-18 backups
were a day old, and `firstRecoverabilityPoint` moved to those. Sidecar logs of the primaries:

```
$ kubectl -n database logs postgres-1 -c plugin-barman-cloud --timestamps | grep -iE 'retention|delet'
03:15:50.501 Applying backup retention policy (retentionPolicy 1d)
03:15:55.013 Deleting backup not in the catalog, backup=postgres-daily-20261117144024
$ kubectl -n keycloak logs keycloak-db-1 -c plugin-barman-cloud --timestamps | grep -iE 'retention|delet'
03:49:03.562 Applying backup retention policy (retentionPolicy 1d)
03:49:09.055 Deleting backup not in the catalog, backup=keycloak-db-daily-20261117144258
```

The bucket afterwards (objects per prefix; two per base backup):

| prefix | base | WAL | 2026-11-19 00:17 UTC |
|---|---|---|---|
| `postgres/` (generation 1) | 10 | 11 | 10 / 11 |
| `keycloak-db/` (generation 1) | 8 | 143 | 8 / 143 |
| `postgres-g2/` | 4 | 2 | 4 / 12 |
| `keycloak-db-g2/` | 4 | 294 | 4 / 411 |

Between the two listings a 2026-11-19 backup was added to each `-g2`
prefix, so the base count stays at four while the oldest backup left.

The base directories `20261117T144227` and `20261117T144532` are gone,
WAL older than the new first backup was removed with them, and
generation 1 was left alone. The same check found D48: the remaining
`postgres` backups had been taken on an idle replica and ended in a WAL
segment that was never archived.

## Day-two tasks

- **Connect.** The `app` user's credentials are in Secret `postgres-app`
  (`username`, `password`, `uri`). Write through `postgres-rw`, read from
  `postgres-ro`.
- **Take a backup now.** Apply a `Backup` as in step 4.
- **Look at the bucket.** `barman-cloud-backup-list` as in the delete
  test; the WAL archive state is in `kubectl cnpg status`.
- **Restore.** Steps 2 to 4 of the check; any time after the first point
  of recoverability shown by `kubectl cnpg status` works.
- **Switch the primary by hand.** `kubectl cnpg promote postgres <instance>
  -n database`.
- **Restart all instances** (for example after changing the sidecar's
  environment): `kubectl cnpg restart postgres -n database`.
- **Upgrade.** Renovate opens upgrade-drill pull requests for the
  operator, the plugin, `kubectl-cnpg` and the PostgreSQL image. Upgrade
  operator and plugin together; check the plugin's release notes for the
  operator version it needs.

## When it goes wrong

- **Drain stops with "cannot delete Pods that declare no controller".**
  Seen in this gate: a local-path helper pod, deleting the restored
  cluster's volume, was still running on the node. It finishes within
  seconds; run the drain again. Do not use `--force`.
- **"Last Failed WAL: 0000000N.history" after a failover.** The new
  primary tries to archive the timeline history while the switchover is
  still recorded as in progress; the operator refuses ("switchover in
  progress, refusing archiving") and the next attempt a second later
  succeeds. Check that "Last Archived WAL" is newer.
- **Restored cluster stops at "Setting up primary".** Not seen here; the
  restore above does not archive. A restored cluster that does archive
  needs its own `serverName` or destination, because the plugin refuses
  to archive into a path that already holds WAL (CloudNativePG recovery
  docs).
- **"Bulk delete failed with 'MissingContentMD5'" in the sidecar log.**
  Expected on this bucket; the deletes that follow one by one succeed.

## Sources

- CloudNativePG 1.30 documentation, from the repository at the release
  tag: supported releases (Kubernetes 1.34 to 1.36, PostgreSQL 14 to 18),
  security (non-root, seccomp, capabilities), backup (`ScheduledBackup`,
  six-field schedule), recovery (`recoveryTarget.targetTime`,
  `externalClusters`, separate `serverName`), container images (Barman no
  longer needed in the image). https://github.com/cloudnative-pg/cloudnative-pg
- CloudNativePG `pkg/versions/versions.go` at v1.30.1: the default image
  `18.6-system-trixie`, which is not used here.
- Barman Cloud Plugin documentation (installation, object stores,
  retention, usage): https://cloudnative-pg.io/plugin-barman-cloud/ ;
  source at v0.16.0: `api/v1/objectstore_types.go` (fields),
  `containers/sidecar-requirements.txt` (barman 3.20.1, boto3 1.43.126,
  no `awscrt`), `internal/cnpgi/instance/retention.go` (retention reads
  the ObjectStore on every run). Issues #770, #918, #1049, #1055.
- Charts: `oci://ghcr.io/cloudnative-pg/charts/cloudnative-pg` 0.29.1 and
  `plugin-barman-cloud` 0.9.0, read with `helm show chart` and
  `helm template`.
- AWS SDK data integrity reference (CRC32C only through the CRT):
  https://docs.aws.amazon.com/sdkref/latest/guide/feature-dataintegrity.html
- Barman 3.20 `retention_policies.py` and `cloud_backup_delete.py`:
  recovery-window semantics and the single-delete fallback.
