# 10 Monitoring

## What this adds

Metrics for the nodes, Kubernetes and every PostgreSQL cluster, and a
Grafana at `https://grafana.lab.savdert.com` that only a user of Keycloak
realm `lab` can open.

```
namespace observability (pod security: privileged, for node-exporter)
  HelmRelease victoria-metrics (release vm, chart victoria-metrics-k8s-stack)
    victoria-metrics-operator  -> turns the VM* resources into pods
    vmagent-vm   scrapes: kubelet, cAdvisor, apiserver, CoreDNS,
                 kube-state-metrics, node-exporter, VMPodScrapes
      -> vmsingle-vm  stores 30 days in PVC vmsingle-vm (20 GiB, local-path)
    vmalert-vm   evaluates the recording and alerting rules
                 (since phase 12: alerts go to vmalertmanager-vm, D47)
    vm-grafana   datasource VictoriaMetrics (type prometheus) -> vmsingle-vm
      <- HTTPRoute grafana.lab.savdert.com <- Gateway network/lab
      -> https://keycloak.lab.savdert.com/realms/lab  (OIDC login)
  VMPodScrape cnpg-instances  every CloudNativePG pod, port metrics (9187)
  VMPodScrape cnpg-operator   the operator in cnpg-system, port metrics (8080)
  HelmRelease cnpg-grafana-dashboards -> ConfigMap with the CloudNativePG dashboard
```

Why VictoriaMetrics and not `kube-prometheus-stack` or an
OpenTelemetry-native stack: D42 in [Decisions](../decisions.md). In short:
the reference repositories give Prometheus alone a 4 GiB limit, the phase
budget for the whole tool is 2 GiB, and VictoriaMetrics accepts OTLP, so
OpenTelemetry can be added later without replacing the store. The login
follows the pattern of Homepage (D43).

## Before you start

- [09 Homepage](09-homepage.md): realm `lab` and user `owner`.
- [07 Database](07-database.md): cluster `postgres` in `database`.
- [05 Ingress](05-ingress.md) and [04 Secrets](04-secrets.md).
- 1Password, vault `homelab-cluster`, item `grafana` (`SECURE_NOTE`),
  created on 2026-11-17 with the `homelab` service account, values
  generated and never printed: `admin-user` (`admin`), `admin-password`,
  `oidc-client-secret`.
- Client `grafana` in realm `lab`. The realm already existed, so the
  operator would not import it again (D41); the client was created with
  `kcadm.sh` and the same definition was written into the
  `KeycloakRealmImport`. The secret went from 1Password into the pod
  through a pipe, without being printed:

  ```
  $ { cat login.sh; printf '%s\n' "\$K create clients -r lab -s clientId=grafana \
      -s publicClient=false -s standardFlowEnabled=true -s directAccessGrantsEnabled=false \
      -s secret='<item grafana, oidc-client-secret>' \
      -s 'redirectUris=[\"https://grafana.lab.savdert.com/login/generic_oauth\"]' \
      -s 'webOrigins=[\"https://grafana.lab.savdert.com\"]' \
      -s 'attributes.\"pkce.code.challenge.method\"=S256' ..."; } \
      | kubectl -n keycloak exec -i keycloak-0 -- sh
  Created new client with id '6decfbb2-d9a6-4fbd-b396-743fb9e37839'
  ```

  `login.sh` is the login block of the Keycloak guide, check step 3.

## Steps

Flux applies the files when they are merged to `main`.

### 1. The stack

`kubernetes/apps/observability/victoria-metrics/`, Flux Kustomization
`victoria-metrics` (after `external-secrets-stores`,
`envoy-gateway-gateway` and `keycloak-realm-lab`):

- `ocirepository.yaml`: the chart from
  `oci://ghcr.io/victoriametrics/helm-charts/victoria-metrics-k8s-stack`,
  0.98.1.
- `helmrelease.yaml`: every value that differs from the chart has a
  comment. The ones that matter:
  - `releaseName: vm`. Without it the release is named after the
    HelmRelease, and the subcharts (Grafana, kube-state-metrics,
    node-exporter) name their objects after the release; they ignore
    `fullnameOverride`. The Service would then be
    `victoria-metrics-grafana`, not `vm-grafana`.
  - CRDs stay plain (`crds.plain: true`, the default) and
    `install.crds`/`upgrade.crds: CreateReplace`. With templated CRDs the
    first install fails: Helm maps the VMAgent and VMSingle of the same
    release before any CRD exists. The chart's CRD cleanup hook, which
    deletes the CRDs and every VM resource on uninstall, is off.
  - `disable_prometheus_converter: true`: there are no Prometheus Operator
    CRDs in the cluster; scrapes are VM resources.
  - etcd, scheduler and controller manager are not scraped (Talos, D42);
    kube-proxy is off by default (Cilium replaces it).
  - Grafana's `role_attribute_path` is written as `"\"'Admin'\""`.
    Grafana's ini parser strips bare single quotes; written as `'Admin'`,
    JMESPath would look up a field `Admin`, find none, and
    `role_attribute_strict` would refuse every login.
- `externalsecret.yaml`: Secret `grafana` from item `grafana`.
- `httproute.yaml`: `grafana.lab.savdert.com`, with the
  `gethomepage.dev/*` annotations that put Grafana on the start page.

The chart's sync Job (a post-install and post-upgrade hook) downloads the
dashboards and rules from upstream `master` branches and creates them as
ConfigMaps and VMRules. They are not in Git and not pinned (accepted in
D42), and an install needs GitHub.

### 2. PostgreSQL

`kubernetes/apps/observability/cnpg-monitoring/`, Flux Kustomization
`cnpg-monitoring` (after `victoria-metrics`, which brings the CRDs):

- `vmpodscrape.yaml`: every pod with label `cnpg.io/podRole: instance` in
  any namespace, and the operator. The Cluster field
  `spec.monitoring.enablePodMonitor` is deprecated and would create a
  Prometheus Operator `PodMonitor`, so it stays off. A new cluster is
  scraped without a change here.
- The dashboard from chart `oci://ghcr.io/cloudnative-pg/grafana-dashboards/cluster`
  0.0.5: a ConfigMap with label `grafana_dashboard: "1"`, which Grafana's
  sidecar loads. Its datasource variable picks the default
  Prometheus-type datasource, VictoriaMetrics.

### 3. Realm `lab`

`kubernetes/apps/keycloak/realm-lab/`: client `grafana` in the
`KeycloakRealmImport`, its secret as placeholder `GRAFANA_CLIENT_SECRET`
from Secret `realm-lab`. The change does nothing to the running realm (the
import stayed `Done`, Keycloak did not restart); it is there for a rebuilt
cluster.

## Check

The gate of phase 10, run on 2026-11-17 after the merge of pull request
47. The cluster has no metrics API (D40), so memory comes from the
kubelet's stats summary. The `kubectl -n observability port-forward`
commands for `svc/vmagent-vm 8429` and `svc/vmsingle-vm 8428` run in the
background.

1. Every pod ready, both releases ready:

   ```
   $ kubectl -n observability get pods
   vm-grafana-6fdd48b4d5-mqnbf                    3/3   Running     0   2m59s
   vm-kube-state-metrics-5fd759d8c6-vdpwk         1/1   Running     0   2m59s
   vm-prometheus-node-exporter-c9f9f              1/1   Running     0   3m
   vm-prometheus-node-exporter-cdrlk              1/1   Running     0   3m
   vm-prometheus-node-exporter-h26x8              1/1   Running     0   3m
   vm-sync-job-6mr98                              0/1   Completed   0   63s
   vm-victoria-metrics-operator-ff6878d49-qh8qq   1/1   Running     0   2m59s
   vmagent-vm-5b9d485f8d-p8jrz                    2/2   Running     0   2m42s
   vmalert-vm-7977dc5cf8-m8zv7                    2/2   Running     0   2m44s
   vmsingle-vm-d8bc4899b-g9hdm                    1/1   Running     0   2m44s
   $ flux get hr -n observability
   cnpg-grafana-dashboards  0.0.5   False  True  Helm install succeeded ... chart cluster@0.0.5
   victoria-metrics         0.98.1  False  True  Helm install succeeded ... chart victoria-metrics-k8s-stack@0.98.1
   ```

2. Every scrape target up, 31 in all, including the kubelet and cAdvisor
   of each Talos node:

   ```
   $ curl -s localhost:8429/api/v1/targets | jq '[.data.activeTargets[] | select(.health != "up")] | length'
   0
   $ curl -s localhost:8429/api/v1/targets | jq -r '.data.activeTargets[] | "\(.health) \(.labels.job)"' | sort | uniq -c
         3 up apiserver
         2 up core-dns
         1 up kube-state-metrics
         9 up kubelet
         3 up node-exporter
         5 up observability/cnpg-instances
         1 up observability/cnpg-operator
         ... (vm-grafana, the operator, vmagent, vmalert, vmsingle: 1 each)
   ```

3. Replication is in the store; the primary `postgres-2` reports two
   streaming replicas:

   ```
   $ curl -s localhost:8428/api/v1/query --data-urlencode 'query=cnpg_pg_replication_streaming_replicas{namespace="database"}' | jq -r '.data.result[] | "\(.metric.pod) \(.value[1])"'
   postgres-2 2
   postgres-1 0
   postgres-3 0
   ```

   The first try, a minute after the install, returned nothing: an instant
   query does not see the newest 30 seconds (`-search.latencyOffset`), and
   there were only a few samples yet.

4. From the owner's device: the sign-in went to Keycloak realm `lab`, the
   login of user `owner` was accepted, "Kubernetes / Compute Resources /
   Nodes Overview" showed CPU and memory for `k8s-1` to `k8s-3`, and the
   CloudNativePG dashboard showed cluster `postgres` with two streaming
   replicas. Before that, from the box:

   ```
   $ curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' https://grafana.lab.savdert.com/login/generic_oauth
   302 https://keycloak.lab.savdert.com/realms/lab/protocol/openid-connect/auth?client_id=grafana&code_challenge=...&code_challenge_method=S256&redirect_uri=...
   ```

5. Memory of every pod in `observability`, in MiB:

   ```
   $ for n in k8s-1 k8s-2 k8s-3; do kubectl get --raw /api/v1/nodes/$n/proxy/stats/summary; done | jq -s '[.[].pods[] | select(.podRef.namespace == "observability") | .memory.workingSetBytes] | add / 1048576'
   933.15234375
   ```

   Read again about seven and a half hours later: 1310 MiB (Grafana 624,
   VMSingle 481, vmagent 66, vmalert 47, operator 43, kube-state-metrics
   21, node-exporter 10 each). Both readings are under 2048.

6. Delete VMSingle; data from before the deletion is still there:

   ```
   $ kubectl -n observability delete pod vmsingle-vm-d8bc4899b-g9hdm
   $ kubectl -n observability wait pod -l app.kubernetes.io/name=vmsingle --for=condition=Ready --timeout=180s
   pod/vmsingle-vm-d8bc4899b-vgqpr condition met
   $ curl -s localhost:8428/api/v1/query_range --data-urlencode 'query=cnpg_pg_replication_streaming_replicas{pod="postgres-2"}' \
       --data-urlencode start=<20 minutes ago> --data-urlencode end=<now> --data-urlencode step=30 | jq ...
   postgres-2: 05:04:00=2 05:04:30=2 05:05:00=2 05:05:30=2 05:06:00=2
   ```

   The pod was deleted at about 05:04:50. The new pod restarted three times
   first; see "When it goes wrong".

## Day-two tasks

- **Upgrade.** Renovate proposes the chart tags. A chart upgrade reruns
  the sync Job, so dashboards and rules can change with it. CRDs are
  replaced by Flux (`upgrade.crds: CreateReplace`).
- **Scrape something new.** A `VMServiceScrape` or `VMPodScrape` next to
  the application; the operator picks it up in any namespace. A chart's own
  `ServiceMonitor` option does not work here (no Prometheus Operator CRDs,
  conversion off).
- **Memory.** The operator gives VMSingle a 1500 MiB limit and vmagent and
  vmalert 500 MiB each; VMSingle sizes its caches from its limit
  (`vm_allowed_memory_bytes` 900 MiB). Grafana and the exporters have no
  limit. The 2 GiB budget is measured, not enforced; repeat gate step 5
  after a few days of data.
- **Who can log in.** Everyone in realm `lab`, as Admin (D43). The local
  `admin` login (item `grafana`) is the way in when Keycloak is down.
  Grafana keeps its database on an `emptyDir`: users and anything changed
  in the UI are lost when the pod restarts; dashboards come back from the
  ConfigMaps.
- **Rotate the client secret.** As for Homepage: regenerate it in Keycloak
  (client `grafana`), put it in item `grafana` field `oidc-client-secret`,
  force the ExternalSecret to refresh (once a day otherwise, D49; the
  annotation is in [Secrets](04-secrets.md)), restart `deploy/vm-grafana`.
  Not tested here.
- **OpenTelemetry later.** VMSingle accepts OTLP metrics over HTTP
  (protobuf) at `http://vmsingle-vm.observability:8428/opentelemetry/v1/metrics`.
  A collector is a separate change with its own record (D42).

## When it goes wrong

- **VMSingle restarts after its pod is deleted.** Seen in gate step 6:
  `cannot acquire lock on file "/victoria-metrics-data/flock.lock":
  resource temporarily unavailable`. The ReplicaSet starts the new pod
  while the old one is still shutting down and holds the lock on the same
  volume. It recovers by itself once the old pod is gone (three restarts,
  about 30 seconds).
- **kubectl suddenly talks to `localhost:8080`.** On 2026-11-17 an
  audit's throwaway `kind` cluster, created from inside the clone, wrote
  into `$KUBECONFIG` (the clone's `kubeconfig`) and left it without a
  current context. `kubectl config use-context admin@homelab` fixes it.
  Give such experiments their own `KUBECONFIG`.
- **Grafana login refused after Keycloak.** Check `role_attribute_path`
  in `kubectl -n observability get cm vm-grafana -o yaml`: it must read
  `"'Admin'"` with both kinds of quotes.
- **Grafana log: `Cannot read directory ... /var/lib/grafana/dashboards/default`.**
  Harmless: the chart's empty default provider. The dashboards come from
  the sidecar.

## Sources

- victoria-metrics-k8s-stack 0.98.1: `Chart.yaml`, `values.yaml`,
  `_helpers.tpl` (the vmalert notifier guard), the operator subchart's
  `templates/crd.yaml` and `crds` subchart.
  https://github.com/VictoriaMetrics/helm-charts/tree/victoria-metrics-k8s-stack-0.98.1/charts/victoria-metrics-k8s-stack
- The chart's documentation page. https://docs.victoriametrics.com/helm/victoria-metrics-k8s-stack/
- VictoriaMetrics operator, Prometheus integration (the converter).
  https://docs.victoriametrics.com/operator/integrations/prometheus/
- VMPodScrape. https://docs.victoriametrics.com/operator/resources/vmpodscrape/
- OpenTelemetry ingestion. https://docs.victoriametrics.com/victoriametrics/integrations/opentelemetry/
- CloudNativePG monitoring: port 9187, `enablePodMonitor` deprecated.
  https://cloudnative-pg.io/docs/current/monitoring
- CloudNativePG dashboards, chart `cluster` 0.0.5.
  https://github.com/cloudnative-pg/grafana-dashboards
- Grafana generic OAuth: `role_attribute_path`, the redirect path.
  https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/generic-oauth/
- Talos etcd metrics (why etcd is not scraped yet).
  https://docs.siderolabs.com/kubernetes-guides/monitoring-and-observability/etcd-metrics.md
- Reference: buroa/home-ops and onedr0p/home-ops observability
  HelmReleases (kube-prometheus-stack 93.3.1, Prometheus limit 4 GiB).
