# ADR-0010: Cilium Ingress + cert-manager private CA for Ingress/TLS

Date: 2026-08-02
Status: Accepted

## Context

Phase 1's last two open items are Ingress+TLS and observability. Right now
the only cluster-exposed service (ArgoCD's UI/API) is reached via
`kubectl port-forward`, which doesn't scale past one operator sitting at
one terminal and isn't representative of how Phase 2's DB tooling
(Grafana, PgAdmin-style UIs, etc.) should be reached.

Two decisions are needed: what terminates/routes HTTP(S) traffic
(Ingress controller), and where TLS certificates come from.

Constraints that shape both:

- Per `docs/PLAN.md`'s explicit out-of-scope list, this cluster is
  **Tailscale-only** — there is no public-facing exposure, no public
  domain, and no public DNS. That rules out the standard "ingress-nginx +
  cert-manager + Let's Encrypt HTTP-01" playbook outright: HTTP-01
  requires a publicly reachable endpoint.
- Per ADR-0008, `k3s-node-01` sits on `10.0.1.0/24` (`k3snet`), reachable
  from any tailnet member via `pve`'s subnet route — no public IP, no
  per-VM Tailscale client.
- The cluster is single-node today (ADR-0005/ADR-0006's `replicas=1`
  caveats already reflect this). Any LB/ingress design should not require
  multi-node assumptions it doesn't need yet.
- Cilium (ADR-0006) is already the CNI, with `kubeProxyReplacement=true`.

## Decision

**Ingress controller: Cilium's built-in Ingress controller**, enabled on
the existing Cilium install (`ingressController.enabled=true`), running in
**`hostNetwork` mode** rather than via a `LoadBalancer` Service. On a
single-node cluster, `hostNetwork` binds Ingress directly to
`k3s-node-01`'s existing `10.0.1.10:80/443` — reachable from the tailnet
today via the ADR-0008 subnet route, no additional moving parts. This
avoids standing up Cilium LB-IPAM + L2 announcements (the homelab
alternative to MetalLB) for a problem a single node doesn't have yet;
revisit when/if the cluster grows past one node, since `hostNetwork` mode
doesn't tolerate multiple backend nodes cleanly.

Cilium's ingress install stays a **manual Helm-CLI change**, consistent
with ADR-0006: Cilium itself is still a day-0 bootstrap component, not yet
handed to ArgoCD (that migration is unrelated cleanup, tracked as a
follow-up, not required to unblock this ADR).

**TLS: cert-manager, with a self-signed private CA**, not public ACME.
Concretely:

1. A bootstrap `Issuer` (`selfsigned-bootstrap`) that can only sign one
   thing: a CA `Certificate`.
2. A CA `Certificate` (`homelab-ca`), signed by the bootstrap issuer,
   whose key material lands in an in-cluster Secret (never committed to
   git — it's generated in-cluster, not sourced from anywhere).
3. A `ClusterIssuer` (`homelab-ca-issuer`) backed by that CA Secret, used
   by every in-cluster `Ingress`/`Certificate` from here on.

cert-manager itself is installed as a **GitOps-managed ArgoCD
Application** from day one (`gitops/apps/cert-manager.yaml`, same
self-referencing Helm-chart-plus-values pattern as `argocd.yaml`) — unlike
Cilium and ArgoCD itself, cert-manager has no chicken-and-egg bootstrap
problem (the CNI and GitOps controller already exist by the time it's
installed), so there's no reason for it to start as an unmanaged manual
step. The `ClusterIssuer`/CA `Certificate` manifests are a second ArgoCD
Application (`gitops/apps/cluster-issuers.yaml`) pointing at plain
manifests, since they're cert-manager *custom resources*, not a Helm
release.

Operators trust `homelab-ca`'s public certificate once, locally (e.g. add
it to the OS/browser trust store), the same one-time-setup cost as
accepting the `pve`/Tailscale trust boundary already implied by
ADR-0008 — this is a private tailnet, not a public service needing
browser-default trust.

Hostnames resolve via a manual per-operator `/etc/hosts` entry pointing at
`10.0.1.10` (e.g. `argocd.homelab.internal`) — there is no in-cluster or
tailnet-wide DNS server yet. This is a deliberate, documented manual step,
not an oversight; revisit if enough hostnames make it unwieldy (a
lightweight split-DNS via Tailscale's own DNS settings, or `dnsmasq` on
`pve`, would be the natural next step, tracked as a future item, not part
of this ADR).

## Alternatives considered

- **ingress-nginx.** The de facto standard with the most tutorials/docs,
  but adds a second dataplane (iptables/userspace proxy) alongside
  Cilium's eBPF one for no functional gain here — Cilium's own Ingress
  controller reuses the CNI's existing eBPF dataplane and stays visible in
  Hubble. Rejected as unnecessary duplication given Cilium is already in
  place.
- **Gateway API instead of classic `Ingress`.** Cilium supports both.
  Gateway API is the more future-facing standard, but `docs/PLAN.md`
  names this item "Ingress + TLS" and classic `Ingress` is simpler to
  reason about for the handful of HTTP services this cluster will expose
  (ArgoCD, Grafana, maybe a DB admin UI) — not worth the extra
  `HTTPRoute`/`Gateway` resource-model complexity yet. Revisit if/when a
  service needs Gateway-API-only features (e.g. TCP/gRPC routing,
  cross-namespace routing policy).
- **Cilium LB-IPAM + L2 announcements (MetalLB-equivalent) instead of
  `hostNetwork`.** Would give Ingress its own stable IP independent of
  which node it schedules to — the right answer for a multi-node cluster.
  Rejected for now: single node means "independent of which node" is a
  non-problem, and `hostNetwork` is strictly less moving parts. Revisit
  when a second `k3s` node joins.
- **Tailscale HTTPS certs (`tailscale serve`/`tailscale cert`, MagicDNS +
  public Let's Encrypt via Tailscale's ACME proxy).** Would give
  browser-trusted-by-default certificates with no local CA trust step,
  and is arguably the more "native" tailnet answer. Rejected for this ADR
  because it requires each exposed service to run through a Tailscale
  sidecar/operator (the [Tailscale Kubernetes
  operator](https://tailscale.com/kb/1236/kubernetes-operator)) that
  isn't in this cluster yet, and ties every ingress hostname to a
  Tailscale-issued identity rather than a general-purpose
  cert-manager/`ClusterIssuer` this repo's DB workloads (Phase 2) can also
  reuse for mTLS between components. Worth revisiting as an alternative
  to the `/etc/hosts` DNS workaround above, but out of scope here.
- **Public ACME via DNS-01** (owning a domain, delegating a zone to a DNS
  provider with an API). Rejected: introduces an external dependency (a
  purchased domain, a DNS provider secret) for a cluster explicitly
  scoped as Tailscale-only with no public-facing intent.

## Consequences

- Cilium gains `ingressController.enabled=true` +
  `ingressController.hostNetwork.enabled=true` via manual `helm upgrade`,
  same operational category as its original install (ADR-0006) — not yet
  GitOps-managed.
- Two new ArgoCD Applications under `gitops/apps/`: `cert-manager.yaml`
  (Helm chart) and `cluster-issuers.yaml` (plain manifests: bootstrap
  `Issuer`, CA `Certificate`, `ClusterIssuer`).
- ArgoCD's own server gains an `Ingress` + cert-manager annotation in
  `gitops/argocd/values.yaml`, replacing `kubectl port-forward` as the
  primary way to reach its UI — verified end to end as part of this
  change.
- Every future in-cluster HTTP service (Grafana, DB admin UIs, etc.) reads
  the same recipe: add an `Ingress` annotated with
  `cert-manager.io/cluster-issuer: homelab-ca-issuer`, add a `/etc/hosts`
  entry, trust `homelab-ca` once per operator machine.
- Foreclosed for now, revisit later: multi-node Ingress HA (needs
  LB-IPAM/L2 instead of `hostNetwork`), tailnet-wide DNS instead of
  per-operator `/etc/hosts`, and Tailscale-native HTTPS certs instead of a
  private CA.

## Update (2026-08-02): Helm values actually required for `hostNetwork` mode

End-to-end verification (`/etc/hosts` entry + trusting `homelab-ca` locally,
then `curl https://argocd.homelab.internal`) surfaced that
`ingressController.enabled=true` +
`ingressController.hostNetwork.enabled=true` alone, as installed at Cilium
day-0 bootstrap time, is **not sufficient** — nothing ends up listening on
the node's port 443. Three additional values were required, applied via
`helm upgrade` (same manual-CLI category as the original install):

1. `ingressController.loadbalancerMode=shared` — the chart's default is
   `dedicated` (one `LoadBalancer` Service + Envoy per Ingress, via
   LB-IPAM), which silently does nothing on a single node with no LB-IPAM
   configured. `shared` is required for `hostNetwork` to actually bind a
   listener.
2. `ingressController.hostNetwork.sharedListenerPort=443` — the chart
   default (`8080`) is an unprivileged port, deliberately chosen upstream to
   avoid the capability issue below. Overridden to `443` so the ADR's
   `https://argocd.homelab.internal` (no port suffix) actually works.
3. `envoy.securityContext.capabilities.envoy` gains `NET_BIND_SERVICE`, plus
   `envoy.securityContext.capabilities.keepCapNetBindService=true` — binding
   port 443 needs `CAP_NET_BIND_SERVICE`, and the chart's
   `cilium-envoy-starter` wrapper drops all capabilities from the forked
   Envoy process unless this flag explicitly keeps that one. (Note the exact
   key name: `keepCapNetBindService`, not `keepNetBindService` — the latter
   is silently accepted by Helm as an unused value and does nothing, which
   cost a debugging round-trip.)

`cilium-agent`'s existing capabilities (`NET_ADMIN`, `SYS_ADMIN`) must be
preserved when overriding `envoy.securityContext.capabilities.envoy` via
`--set` with indexed keys — replacing the list wholesale drops them and
crash-loops the datapath.

Verified after the fix: `cilium-envoy` binds `0.0.0.0:443`,
`curl https://argocd.homelab.internal` returns `200` with
`SSL certificate verify ok` against the locally-trusted `homelab-ca`.

This was applied imperatively (`helm upgrade --reuse-values --set ...`),
matching how Cilium was installed in the first place — not yet captured as
a file in this repo. Tracked as follow-up work: fold these values into a
checked-in `values.yaml` (mirroring `gitops/argocd/values.yaml`'s pattern)
so a from-scratch rebuild doesn't have to rediscover them by hand.
