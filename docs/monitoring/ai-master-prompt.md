# ROLE AND OBJECTIVE
You are an expert Senior Kubernetes Site Reliability Engineer (SRE) and Observability Architect. Your task is to design and bootstrap a highly scalable, production-ready, GitOps-driven observability stack for my Kubernetes cluster. 

Do NOT generate any generic or outdated manifests. You MUST use the latest stable versions of all tools as of 2026. Before generating any code, use your search/web-browsing capabilities to read the latest official documentation for OpenTelemetry Operator, Altinity ClickHouse Operator, and Grafana LGTM Helm charts.

# ENVIRONMENT & CONSTRAINTS
You must design the manifests to natively integrate with my existing infrastructure:
1.  **Deployment Model:** GitOps via **ArgoCD**. Output all manifests structured as ArgoCD `Application` resources or an `App of Apps` pattern.
2.  **Secret Management:** **1Password Kubernetes Operator**. DO NOT put any plaintext passwords, API keys, or tokens in the manifests. Use `OnePasswordItem` CRDs to inject secrets (like DB passwords, Grafana admin passwords, Cloudflare tokens) into the deployments.
3.  **Networking & Routing:** **Cilium CNI**. Use Cilium's native `CiliumIngress` or Kubernetes standard `Ingress` (configured for Cilium ingress controller) for exposing web UI endpoints.
4.  **External Access:** **Cloudflare Tunnel** (`cloudflared`). The Grafana UI must be exposed securely via Cloudflare Tunnel using local Cilium Ingress routing.

# ARCHITECTURE REQUIREMENTS

## 1. Storage & Backend Tier (Dual-Target)
* **LGTM Stack:** Set up a lightweight version of Loki, Grafana, Tempo, and Mimir (or VictoriaMetrics as a drop-in replacement for Prometheus remote-write). 
* **ClickHouse (OLAP):** Set up a production-ready ClickHouse cluster using the **Altinity ClickHouse Operator**. Include **ClickHouse Keeper** (do NOT use Zookeeper). Ensure `StorageClass` is set for fast local storage (e.g., local-path).

## 2. Telemetry Pipeline (OpenTelemetry - The Core)
* Deploy the **OpenTelemetry Operator**.
* **OTel Agent (DaemonSet):** Must collect node metrics (kubeletstats), Talos/OS host metrics, and pod logs. It must NOT process data; it must forward everything directly to the OTel Gateway.
* **OTel Gateway (Deployment + HPA):** This is the central processing unit. It must receive OTLP data, apply batching, memory limiting, and tail-sampling for traces.
* **Forking Pipeline:** The Gateway MUST export telemetry data to TWO destinations simultaneously: 
    1. The LGTM stack (Prometheus Remote Write, Loki, Tempo).
    2. ClickHouse (using the `clickhouse` exporter to create `otel_logs`, `otel_metrics`, `otel_traces` tables).

## 3. Auto-Instrumentation (eBPF)
* Deploy **Grafana Beyla (OpenTelemetry eBPF Instrumentation - OBI)** as a `DaemonSet`.
* Configure Beyla to run with the necessary Linux capabilities/privileges for eBPF.
* Beyla must capture RED metrics and HTTP/gRPC/SQL traces from all application pods automatically and push them in OTLP format to the **OTel Gateway**.

# STRICT BANNED TOOLS
Do NOT use or suggest the following legacy tools: Promtail, FluentBit, Fluentd, Jaeger Agent, Telegraf, Grafana Alloy, or Grafana Agent. Everything MUST flow through OpenTelemetry (OTLP).

# EXECUTION STEPS (Follow Sequentially)
1.  **Acknowledge & Plan:** Briefly outline the directory structure for the GitOps repository you are about to create.
2.  **Research:** Silently search the web for the latest Helm chart versions and CRD apiVersions for OTel Operator, Altinity Operator, and Cilium Ingress.
3.  **Generate Secrets YAMLs:** Provide the `OnePasswordItem` templates required for the stack.
4.  **Generate Backend YAMLs:** ClickHouse and LGTM stack configurations (Helm values files tailored for ArgoCD).
5.  **Generate OTel Pipeline YAMLs:** The `OpenTelemetryCollector` CRDs for both Agent and Gateway, containing the complex routing pipelines.
6.  **Generate Beyla YAMLs:** The eBPF DaemonSet configuration.
7.  **Generate Ingress/Tunnel YAMLs:** Cilium Ingress and Cloudflare Tunnel configurations for accessing Grafana.

Ensure all YAMLs are perfectly formatted, well-commented, and ready to be committed to a Git repository.
---
Soruların ve mimariyi sorgulaman çok yerinde. SRE yaklaşımını takdir ettim. İşte kararlarımız ve devam etmen için net yönergeler:

1. "Alloy Yasak" kararımda KESİNLİKLE kararlıyım. OTel Collector'ın log toplamadaki zorluklarının (filelog + k8sattributes config) farkındayım. Vendor-agnostic kalmak istiyorum. Kubernetes namespace/pod label'larının loglara düzgün bindirildiğinden emin olacak, production kalitesinde bir OTel Agent DaemonSet config'i yaz.

2. Beyla eBPF yetkileri (Talos OS): Talos OS'in güvenlik modeli kısıtlamalarının farkındayım. Beyla'nın DaemonSet manifestosunu, 'securityContext' altında gerekli 'CAP_BPF', 'CAP_SYS_ADMIN' vb. yeteneklerle donat. Ayrıca Talos ortamında bu podun PSA (Pod Security Admission) kısıtlamalarına takılmaması için gereken Namespace seviyesindeki label'ları veya istisnaları manifestolara ekle.

3. Dual-Target (LGTM + ClickHouse): Evet, kesinlikle Dual Stack istiyorum. Ana izleme yapımı LGTM (Loki, Tempo, VictoriaMetrics) üzerinde kurgulayacağım. Ancak ClickHouse'u öğrenmek için OTel Gateway üzerinden veriyi (log, metric, trace) "fork" edip ClickHouse'a da basmanı istiyorum.

4. Mimir vs VictoriaMetrics: Haklısın, Mimir'in S3 bağımlılığı ve ağırlığına girmek istemiyorum. Mimir yerine kesinlikle VictoriaMetrics (Single node veya düşük kaynaklı cluster) kullan. OTel Gateway'in exporter'ını VictoriaMetrics'in remote-write portuna yönlendir.

5. ClickHouse HA: ClickHouse'u öğrenme/ikincil hedef olarak konumlandırdığım için 3 replica + Keeper gibi devasa bir HA mimarisine ihtiyacım yok. Single Node olarak yapılandır, fakat hızlı disk kullanımı için local-path StorageClass ayarını düzgün yap.

Lütfen bu mimari kararlar doğrultusunda GitOps repo klasör yapısını ve ArgoCD/Manifest dosyalarını (1Password, Cilium Ingress dahil) sıfırdan oluşturmaya başla.

---

## Environment Variables and Architecture Decisions

The Beyla + OTel Agent → Gateway → Dual Target diagram is correct. Proceeding with
this architecture. The `Instrumentation` CRD is not needed.

**1. Cluster Nodes and Resources:**
- Environment: Homelab running Talos OS on Proxmox (and Hetzner).
- Worker nodes: 3 nodes, each with ~4 Core / 16 GB RAM.
- OTel Agent and Beyla: DaemonSet — 1 pod per node.
- OTel Gateway: HPA min:1, max:3. Resources: request 256m CPU / 512Mi RAM, limit 1000m CPU / 2Gi RAM.

**2. StorageClass — local-path (not Longhorn):**
- Longhorn is network-attached storage — too much I/O overhead for write-heavy databases.
- Use `local-path` provisioner for ClickHouse and VictoriaMetrics for direct disk access.

**3. 1Password Vault and Item Names:**
- Vault: `homelab`
- Items to create:
  - `grafana-admin-credentials` (fields: username, password)
  - `clickhouse-admin-credentials` (fields: username, password)

**4. Namespace Strategy:**
- `monitoring` → LGTM stack (VictoriaMetrics, Loki, Tempo, Grafana)
- `clickhouse` → ClickHouse only (no HyperDX)
- `observability` → OTel Operator, Agent, Gateway, Beyla

**5. Talos Machine Config and eBPF:**
- Talos version: v1.7+
- Add `privileged: true` and `hostPID: true` to the Beyla DaemonSet.
- Provide a `talos-patch.yaml` with the kernel parameters and PSA exemptions required
  for eBPF (bpf_jit_enable, perf_event_paranoia, unprivileged_bpf_disabled).

**6. Existing Cloudflare Tunnel:**
- No new tunnel needed — use the existing `cloudflare-tunnel` namespace deployment.
- The wildcard `*.savdert.com` DNS entry picks up any new Cilium Ingress automatically.
- Use `ingressClassName: cilium` with `host: grafana.savdert.com` for Grafana.