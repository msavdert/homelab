# VictoriaMetrics Shared Stack

The core monitoring engine providing long-term storage, scraping, and visualization.

## 1. Components
- **VMSingle:** High-performance single-binary database for long-term metric storage.
- **VMAgent:** Efficient metric scraper (optional, as OTel Collector will be primary).
- **VMAlert:** Rule evaluation engine for metrics-based alerting.

## 2. Architecture & Performance
- **Sync Wave:** `7`
- **Storage:** Uses `longhorn-db` StorageClass with 20Gi capacity and 30-day retention.
- **Scraping:** While VMAgent is available, the cluster-wide strategy favors OpenTelemetry Collectors for metric ingestion.

## 3. Best Practices (AGENTS.md Compliance)
- **Persistence:** All stateful components use Longhorn with `replicaCount: 1`.
- **Resource Limits:** Defined to prevent resource exhaustion on worker nodes.
- **Data Locality:** Database storage is optimized via `longhorn-db`.

## 4. References
- [VMSingle Documentation](https://docs.victoriametrics.com/vmsingle/)
- [VMAgent Documentation](https://docs.victoriametrics.com/vmagent/)
- [Grafana Helm Chart](https://github.com/grafana/helm-charts)
