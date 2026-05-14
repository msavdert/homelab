# Troubleshooting

Common issues and debugging commands for the observability stack.

## Quick Diagnostics

```bash
# Overall health check
kubectl get pods -n observability -o wide
kubectl get pods -n monitoring -o wide
kubectl get pods -n clickhouse -o wide
kubectl get applications -n argocd | grep -E "observability|monitoring|clickhouse|victoria|loki|tempo|grafana"

# Check HPA status
kubectl get hpa -n observability

# Check PVCs
kubectl get pvc -n monitoring
kubectl get pvc -n clickhouse
```

---

## OTel Agent Issues

### Agent pods not starting

**Symptom:** Agent pods stuck in `Pending` or `CrashLoopBackOff`.

**Check PSA:**
```bash
kubectl describe pod -n observability <agent-pod> | grep -A5 "Events:"
```
If you see `violates PodSecurity`, the `observability` namespace PSA exemption is missing.
Apply `talos/beyla-ebpf-patch.yaml` and reboot nodes.

**Check RBAC:**
```bash
kubectl auth can-i list pods --as=system:serviceaccount:observability:otel-agent -n default
# Should return: yes
```

### Agent not collecting kubeletstats

**Symptom:** No `k8s.pod.*` or `k8s.node.*` metrics in VictoriaMetrics.

**Check kubelet connectivity:**
```bash
kubectl exec -n observability <agent-pod> -- \
  wget -qO- --no-check-certificate \
  "https://$K8S_NODE_NAME:10250/stats/summary" 2>&1 | head -5
```

If this fails, the Agent ServiceAccount lacks `nodes/stats` permission. Check the
ClusterRole in `apps/base/observability/rbac.yaml`.

### Agent not collecting logs

**Symptom:** No logs in Loki or ClickHouse.

**Check filelog is reading files:**
```bash
kubectl exec -n observability <agent-pod> -- ls /var/log/pods/ | head -10
```

If empty, the `/var/log/pods` hostPath mount is not working. Check the DaemonSet spec.

**Check for parsing errors:**
```bash
kubectl logs -n observability <agent-pod> | grep -i "error\|failed\|parse"
```

### Agent sending to Gateway but Gateway not receiving

**Check Gateway service:**
```bash
kubectl get svc -n observability | grep gateway
kubectl port-forward -n observability svc/otel-gateway-collector 4317:4317 &
# Try sending a test span
```

**Check network policy:**
```bash
kubectl get networkpolicy -n observability
```

---

## OTel Gateway Issues

### Gateway not forwarding to VictoriaMetrics

**Symptom:** Metrics in Agent logs but not in VictoriaMetrics.

**Check Gateway logs:**
```bash
kubectl logs -n observability \
  -l app.kubernetes.io/name=otel-gateway-collector \
  --tail=50 | grep -i "victoria\|remote_write\|error"
```

**Test VictoriaMetrics connectivity from Gateway:**
```bash
kubectl exec -n observability <gateway-pod> -- \
  wget -qO- "http://victoriametrics.monitoring.svc.cluster.local:8428/health"
# Should return: OK
```

### Gateway not forwarding to Loki

**Check Loki connectivity:**
```bash
kubectl exec -n observability <gateway-pod> -- \
  wget -qO- "http://loki.monitoring.svc.cluster.local:3100/ready"
# Should return: ready
```

**Check for label cardinality errors:**
```bash
kubectl logs -n observability <gateway-pod> | grep -i "loki\|stream\|label"
```
If Loki rejects writes due to too many streams, reduce the number of stream labels
in the Gateway's Loki exporter config.

### Gateway not forwarding to ClickHouse

**Check ClickHouse connectivity:**
```bash
kubectl exec -n observability <gateway-pod> -- \
  wget -qO- "http://clickhouse.clickhouse.svc.cluster.local:8123/ping"
# Should return: Ok.
```

**Check the otel_writer password:**
```bash
kubectl get secret -n observability clickhouse-admin-credentials -o jsonpath='{.data.password}' | base64 -d
```

Compare with the password in ClickHouse:
```bash
kubectl exec -n clickhouse <ch-pod> -- \
  clickhouse-client --user admin --password "$CH_PASS" \
  --query "SELECT name FROM system.users"
```

### Tail sampling dropping too many traces

**Symptom:** Very few traces in Tempo or ClickHouse.

**Check sampling decision logs:**
```bash
kubectl logs -n observability <gateway-pod> | grep -i "sampling\|decision"
```

**Increase sampling percentage** in `apps/base/observability/otel-gateway.yaml`:
```yaml
- name: probabilistic-policy
  type: probabilistic
  probabilistic:
    sampling_percentage: 50   # increase from 10%
```

**Check if tail_sampling buffer is full:**
```bash
kubectl logs -n observability <gateway-pod> | grep "num_traces"
```
If the buffer is full (50,000 traces), increase `num_traces` or reduce `decision_wait`.

---

## Beyla Issues

### Beyla pods not starting

**Symptom:** Beyla pods in `Pending` or `Error`.

**Check PSA:**
```bash
kubectl describe pod -n observability <beyla-pod> | grep -A10 "Events:"
```
`violates PodSecurity` → apply Talos patch and reboot nodes.

**Check capabilities:**
```bash
kubectl describe pod -n observability <beyla-pod> | grep -A5 "Capabilities"
```

### Beyla running but no metrics

**Check if Beyla can see host processes:**
```bash
kubectl exec -n observability <beyla-pod> -- ls /proc | wc -l
# Should return a large number (hundreds of PIDs)
# If it returns ~5, hostPID is not working
```

**Check eBPF probe attachment:**
```bash
kubectl logs -n observability <beyla-pod> | grep -i "instrument\|attach\|probe\|error"
```

**Verify kernel parameters on the node:**
```bash
talosctl read /proc/sys/kernel/perf_event_paranoia --nodes <node-ip>
# Expected: 1

talosctl read /proc/sys/kernel/unprivileged_bpf_disabled --nodes <node-ip>
# Expected: 0
```

### Beyla producing metrics but not traces

**Check trace sampling config:**
```bash
kubectl get configmap -n observability beyla-config -o yaml | grep -A5 "sampler"
```

The default is 10% head sampling. If you need more traces, increase `arg` to `"1.0"`.

---

## VictoriaMetrics Issues

### No data in VictoriaMetrics

**Check remote write is reaching VictoriaMetrics:**
```bash
kubectl port-forward -n monitoring svc/victoriametrics 8428:8428 &
curl "http://localhost:8428/api/v1/query?query=vm_rows_inserted_total" | python3 -m json.tool
```

If `vm_rows_inserted_total` is 0 or not found, no data has been written.

**Check VictoriaMetrics logs:**
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=victoria-metrics-single --tail=30
```

### VictoriaMetrics PVC full

```bash
kubectl exec -n monitoring <vm-pod> -- df -h /storage
```

If the disk is full, increase the PVC size or reduce retention:
```yaml
server:
  retentionPeriod: 30d   # reduce from 90d
```

---

## Loki Issues

### Logs not appearing in Grafana

**Check Loki is receiving data:**
```bash
kubectl port-forward -n monitoring svc/loki 3100:3100 &
curl "http://localhost:3100/loki/api/v1/labels" | python3 -m json.tool
```

If the labels list is empty, no logs have been ingested.

**Check Loki ingestion rate limits:**
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=loki --tail=30 | grep -i "rate\|limit\|error"
```

If you see rate limit errors, increase the limits in `apps/production/loki.yaml`:
```yaml
limits_config:
  ingestion_rate_mb: 32
  per_stream_rate_limit: 20MB
```

---

## ClickHouse Issues

### ClickHouse pod not starting

**Check operator logs:**
```bash
kubectl logs -n clickhouse \
  -l app.kubernetes.io/name=clickhouse-operator \
  --tail=30
```

**Check ClickHouseInstallation status:**
```bash
kubectl describe chi -n clickhouse clickhouse | tail -30
```

### otel database not created

**Check if the init Job ran:**
```bash
kubectl get jobs -n clickhouse
kubectl logs -n clickhouse job/clickhouse-otel-init
```

If the Job failed, run it manually:
```bash
kubectl delete job -n clickhouse clickhouse-otel-init
# ArgoCD will recreate it on next sync (hook: Sync)
kubectl annotate application clickhouse -n argocd \
  argocd.argoproj.io/refresh=hard
```

### ClickHouse password mismatch

**Symptom:** OTel Gateway logs show authentication errors for ClickHouse.

**Check the secret:**
```bash
kubectl get secret -n clickhouse clickhouse-admin-credentials \
  -o jsonpath='{.data.password}' | base64 -d
```

**Check the 1Password item was synced:**
```bash
kubectl get onepassworditem -n clickhouse
kubectl describe onepassworditem -n clickhouse clickhouse-admin-credentials
```

---

## ArgoCD Sync Issues

### Application stuck in OutOfSync

**Force a refresh:**
```bash
argocd app get <app-name> --refresh
argocd app sync <app-name>
```

**Check for ignoreDifferences issues:**
```bash
argocd app diff <app-name>
```

### ClickHouseInstallation constantly OutOfSync

The Altinity Operator mutates the `status` field at runtime. This is handled by
`ignoreDifferences` in `apps/production/clickhouse.yaml`. If it's still showing
OutOfSync, check:

```bash
kubectl get chi -n clickhouse clickhouse -o yaml | grep -A5 "status:"
```

Add the specific JSON pointer to `ignoreDifferences` if needed.

---

## Grafana Operator Issues

### GrafanaDatasource not syncing

**Symptom:** Datasource exists as a CR but doesn't appear in Grafana UI.

**Check operator logs:**
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana-operator --tail=30
```

**Check datasource CR status:**
```bash
kubectl describe grafanadatasource -n monitoring victoriametrics
```

Look for `status.conditions` — should show `Ready: True`.

**Check instanceSelector matches:**
The `GrafanaDatasource` CR's `instanceSelector.matchLabels` must match the `Grafana`
CR's `metadata.labels`:
```bash
kubectl get grafana -n monitoring grafana -o jsonpath='{.metadata.labels}'
# Should include: dashboards=grafana
```

### Grafana pod not starting

**Check PVC:**
```bash
kubectl get pvc -n monitoring | grep grafana
```

If the PVC is `Pending`, the `local-path` provisioner may not be installed.

**Check admin credentials Secret:**
```bash
kubectl get secret -n monitoring grafana-admin-credentials
kubectl get onepassworditem -n monitoring grafana-admin-credentials
```

---

## Tempo Operator Issues

### TempoMonolithic not creating pods

**Check operator logs:**
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=tempo-operator --tail=30
```

**Check CR status:**
```bash
kubectl describe tempomonolithic -n monitoring tempo-monolithic
```

**Check cert-manager is working** (Tempo Operator uses cert-manager for webhooks):
```bash
kubectl get certificate -n monitoring
kubectl get certificaterequest -n monitoring
```

### Tempo not receiving traces

**Check the service name:**
The Tempo Operator creates a Service named `tempo-monolithic` (not `tempo`).
Verify the OTel Gateway is pointing to the correct endpoint:
```bash
kubectl get svc -n monitoring | grep tempo
# Should show: tempo-monolithic   ClusterIP   ...   4317/TCP,4318/TCP
```

If the Gateway config still references `tempo.monitoring.svc.cluster.local:4317`,
update it to `tempo-monolithic.monitoring.svc.cluster.local:4317`.

---

```bash
# Get all events in a namespace (sorted by time)
kubectl get events -n observability --sort-by='.lastTimestamp' | tail -20

# Check resource usage
kubectl top pods -n observability
kubectl top pods -n monitoring
kubectl top pods -n clickhouse

# Check OTel Collector internal metrics (port 8888)
kubectl port-forward -n observability <agent-pod> 8888:8888 &
curl http://localhost:8888/metrics | grep otelcol_receiver_accepted

# Check Gateway queue sizes
kubectl port-forward -n observability <gateway-pod> 8888:8888 &
curl http://localhost:8888/metrics | grep otelcol_exporter_queue_size

# Verify ClickHouse table sizes
kubectl exec -n clickhouse <ch-pod> -- \
  clickhouse-client --user admin --password "$CH_PASS" \
  --query "
    SELECT table,
           formatReadableSize(sum(bytes_on_disk)) AS size,
           sum(rows) AS rows
    FROM system.parts
    WHERE database = 'otel' AND active = 1
    GROUP BY table
    ORDER BY sum(bytes_on_disk) DESC
    FORMAT PrettyCompact"
```
