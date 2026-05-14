# Architecture Decision Record

This document records the key architectural decisions made before building the new
observability stack, including the options considered and the rationale for each choice.

## Decision 1: OTel Operator — Required or Not?

### What the OTel Operator Does

The OpenTelemetry Operator provides two capabilities:

**1. Auto-instrumentation** — Injects the OTel SDK into Java/Python/Node.js/Go/.NET
applications without code changes. It adds an init container to the pod that loads the
SDK before the application starts. The application then automatically produces traces,
metrics, and logs.

```yaml
# Adding this annotation to a namespace auto-instruments all pods in it
instrumentation.opentelemetry.io/inject-java: "true"
```

**2. Collector management** — Manages `OpenTelemetryCollector` CRD deployments in
Kubernetes-native fashion (sidecar, daemonset, and deployment modes).

### Is the OTel Operator Required When Using Alloy?

**No** — if auto-instrumentation is not needed.

Alloy already handles:
- Kubernetes pod/node metric collection
- Pod log collection
- OTLP receiver for application traces
- Fan-out to multiple backends

The `OpenTelemetryCollector` CRD does not replace Alloy — it is simply an alternative
way to manage OTel Collector deployments.

### When Is the OTel Operator Needed?

- When you want to add traces/metrics to applications without touching their code
- When you want to instrument Java/Python/Node.js applications running in Kubernetes
  with zero code changes
- When you want to manage different collector configurations per namespace

### Decision

**Use the OTel Operator.** The new stack uses `OpenTelemetryCollector` CRDs (managed
by the Operator) for both the Agent and Gateway. The `Instrumentation` CRD
(SDK auto-injection) is **not used** — Beyla handles instrumentation via eBPF instead.

---

## Decision 2: Grafana Alloy vs. OTel Collector

### Comparison

| Feature | Grafana Alloy | OTel Collector |
|---------|--------------|----------------|
| Kubernetes log collection | ✅ Native (`loki.source.kubernetes`) | ⚠️ Possible via `filelog` receiver |
| Kubernetes metric scraping | ✅ Native (`prometheus.scrape`) | ⚠️ Possible via `prometheus` receiver |
| OTLP receiver | ✅ | ✅ |
| Fan-out (multiple backends) | ✅ Native | ✅ |
| Configuration language | Alloy (HCL-like) | YAML |
| Grafana ecosystem integration | ✅ Excellent | ⚠️ Requires extra config |
| ClickHouse exporter | ❌ Not available | ✅ `clickhouseexporter` available |
| Community | Grafana | CNCF |
| Vendor neutrality | ❌ Grafana-tied | ✅ Vendor-agnostic |

### Decision

**OTel Collector only. Alloy is banned.**

The goal is a vendor-agnostic, OTel-native pipeline. The OTel Collector's `filelog`
receiver requires more configuration than Alloy's `loki.source.kubernetes`, but this
complexity is handled explicitly in the Agent config (`apps/base/observability/otel-agent.yaml`).

The ClickHouse exporter availability in OTel Collector contrib is a key factor — it
enables direct writes to ClickHouse without an intermediate component.

---

## Decision 3: Dual-Target Architecture

### Rationale

The stack sends all telemetry to two destinations simultaneously:

1. **LGTM stack** (VictoriaMetrics + Loki + Tempo + Grafana) — primary production
   observability system with long retention
2. **ClickHouse** — analytics and learning target with short retention (72h TTL)

The OTel Gateway implements this via named pipeline pairs:
```
metrics          → VictoriaMetrics
metrics/clickhouse → ClickHouse
logs             → Loki
logs/clickhouse  → ClickHouse
traces           → Tempo
traces/clickhouse → ClickHouse
```

Each pipeline pair is independent — a ClickHouse outage does not affect the LGTM pipeline.

---

## Decision 4: Mimir vs. VictoriaMetrics

### Mimir

- Grafana's long-term metrics storage
- Requires S3 or compatible object storage
- Designed for multi-tenant, high-scale deployments
- Operationally complex for a homelab

### VictoriaMetrics

- Drop-in Prometheus replacement
- Accepts Prometheus remote write at `/api/v1/write`
- Runs as a single binary with local storage
- Better compression than Prometheus TSDB
- Simpler operation — no object storage dependency

### Decision

**VictoriaMetrics Single.** The homelab has no S3 infrastructure. VictoriaMetrics
provides better performance than Prometheus with simpler operation than Mimir.

---

## Decision 5: ClickHouse HA vs. Single Node

### HA Setup (3 replicas + 3 Keeper nodes)

- Survives node failures
- Requires 6 pods minimum
- Keeper adds operational complexity
- Appropriate for production data

### Single Node

- 1 ClickHouse pod, no Keeper
- Simple to operate
- Data loss risk on node failure
- Appropriate for analytics/learning data with short TTL

### Decision

**Single node.** ClickHouse is the analytics and learning target. Data has a 72-hour
TTL — losing it on a node failure is acceptable. The operational simplicity of a single
node outweighs the HA benefits for this use case.

---

## Decision 6: StorageClass — Longhorn vs. local-path

### Longhorn

- Network-attached storage with replication
- Data survives node failures
- Network I/O overhead for every read/write
- Appropriate for stateful workloads that need HA

### local-path

- Direct disk access, no network overhead
- High IOPS for write-heavy workloads
- Creates node affinity (pod cannot move to another node)
- Data loss risk on node failure

### Decision

**local-path for ClickHouse and VictoriaMetrics.** Both are write-heavy databases
that benefit significantly from local I/O. The node affinity tradeoff is acceptable
for a homelab where node failures are rare and data retention is short.

Loki and Tempo also use local-path for the same reason.

---

## Decision 7: Beyla for Auto-Instrumentation

### SDK Injection (OTel Operator `Instrumentation` CRD)

- Injects OTel SDK into application pods
- Requires pod restart for each instrumented application
- Language-specific (separate config per language)
- Produces high-quality traces with full context

### Beyla (eBPF)

- No code changes, no pod restarts
- Language-agnostic (works for any HTTP/gRPC/SQL service)
- Requires elevated kernel privileges
- Produces RED metrics and traces automatically
- Slightly less context than SDK-based traces (no custom spans)

### Decision

**Beyla.** The zero-code, language-agnostic approach is more practical for a homelab
where many different services run. The elevated privilege requirement is handled by
the Talos machine config patch.
