# ADR-0007: ArgoCD as the GitOps controller

Date: 2026-08-02
Status: Accepted

## Context

ADR-0005 fixed k3s on Debian VMs, ADR-0006 fixed Cilium as the CNI. The
next open Phase 1 item is the GitOps tool that will own the cluster's
ongoing desired state: Cilium's day-2 lifecycle (per ADR-0006), ingress/
TLS, observability, and — starting in Phase 2 — the Postgres/MySQL HA
operators themselves.

Two realistic options: ArgoCD and Flux. Both are CNCF-graduated, both
support Kustomize and Helm sources, both work identically well against a
single-node k3s cluster reachable only over Tailscale. Neither has a
direct, non-cosmetic effect on database-reliability outcomes the way the
CNI choice did (Hubble's flow visibility was a real DBRE diagnostic
tool) — this decision sits closer to platform ergonomics and portfolio
presentation than to Phase 2 depth, so the usual "prefer DBRE clarity"
tie-breaker doesn't cleanly separate them.

Relevant differences found:

- **Architecture.** ArgoCD is application-centric with its own API
  server, repo server, and web UI — a real control plane. Flux is a set
  of four lightweight controllers (source, kustomize, helm,
  notification) with no UI, driven by CLI/YAML and `kubectl get`-style
  inspection.
- **Helm handling.** ArgoCD treats Helm as a manifest-rendering step
  (`helm template`, then apply). Flux's `HelmRelease` CRD treats Helm as
  a first-class delivery mechanism, with kstatus-based health checking
  that understands whether a StatefulSet's replicas actually became
  ready, not just whether the apply succeeded. This matters more for
  Phase 2's Postgres/MySQL HA operators than for anything in Phase 1.
- **Secrets (SOPS).** ADR-0003 already committed this repo to SOPS +
  age. Flux's `kustomize-controller` has *native* SOPS decryption
  (`spec.decryption.provider: sops`) — no extra component. ArgoCD has no
  built-in SOPS support; it needs a Config Management Plugin sidecar
  (KSOPS, or the `helm-secrets` plugin) wired in separately. This is a
  real point in Flux's favor, not a wash.
- **Resource footprint.** Flux is lighter (no UI/API/repo server). On
  this host (12 CPU / 128 GB RAM, single node) this difference is not a
  practical constraint either way.
- **Portfolio visibility.** ArgoCD's web UI gives an at-a-glance view of
  sync status, drift, and app health — useful both for day-to-day
  operation and for a reviewer evaluating this repo to see GitOps state
  without reading YAML or running CLI commands. ArgoCD also has
  significantly wider adoption (cited around 60% of clusters doing
  GitOps-style delivery), which carries some signal value in a
  career-transition portfolio context.
- **Sync model.** ArgoCD's `ApplicationSet` controller can template
  multiple `Application` resources from one generator — a good fit for
  Phase 2, where Postgres HA and MySQL HA will likely be structured as
  parallel, similarly-shaped app definitions rather than one bespoke
  app each.

## Decision

Run **ArgoCD** as the GitOps controller, using the App-of-Apps pattern:
one root `Application` (managed by Terraform or applied manually at
bootstrap) that points at a directory of child `Application` manifests
in this repo, one per component (Cilium config, ingress/TLS,
observability stack, and later the Phase 2 database operators).
`ApplicationSet` is adopted once Phase 2 needs to template
near-identical Application definitions across multiple DB workloads,
rather than from day one.

The deciding factor is operational visibility for a portfolio project:
being able to show — to the operator during a failover drill, and to a
reviewer afterward — exactly what Git state is live, what has drifted,
and what synced when, without CLI-only introspection, is worth more
here than Flux's leaner footprint or its native SOPS support. The SOPS
gap is real but solvable (KSOPS sidecar) and is tracked explicitly under
Consequences below, not ignored.

Like Cilium (ADR-0006), ArgoCD's own installation is a **day-0 manual
bootstrap step**, not self-managed from the start: it must exist before
it can reconcile anything, so its initial install happens via Helm CLI
against the freshly bootstrapped, Cilium-enabled cluster. Once running,
ArgoCD is handed its own `Application` (pointing at its own Helm chart
values in this repo) so its subsequent upgrades and config changes flow
through GitOps like everything else — "day-0 manual, day-2
GitOps-managed," the same split ADR-0006 flagged as an open question for
this ADR to resolve.

## Alternatives considered

- **Flux.** Rejected, closer call than it looks at first glance. Its
  native SOPS decryption and deeper Helm/kstatus integration are
  genuine advantages for Phase 2's HA operators, and its lighter
  footprint would be the correct default for a resource-constrained or
  edge-style deployment. It loses out here because this project's other
  half of the value (see `CLAUDE.md`) is being legible to an outside
  reviewer, and ArgoCD's UI plus its dominant adoption serve that
  better than Flux's CLI-first, background-infrastructure posture.
  Revisit if the KSOPS integration proves painful enough in practice to
  outweigh the UI benefit — that would be a signal this call was wrong.

## Consequences

- ArgoCD is installed manually (Helm) as a day-0 bootstrap step after
  k3s + Cilium are up; it then manages its own subsequent lifecycle via
  a self-referencing `Application`.
- SOPS-encrypted secrets need a Config Management Plugin (KSOPS is the
  leading candidate) wired into ArgoCD's repo-server before any
  encrypted manifest can be synced — this is new setup work Flux would
  not have required, and should be resolved before the ingress/TLS or
  observability items land any real credentials.
- App-of-Apps is the starting structure; `ApplicationSet` is deferred
  until Phase 2 needs to template multiple similarly-shaped DB-operator
  Applications, not adopted preemptively.
- Cilium's ongoing config (per ADR-0006) becomes an ArgoCD `Application`
  pointing at the Cilium Helm chart, once ArgoCD itself is up.
- Revisit this decision if KSOPS/CMP maintenance becomes a recurring
  time sink relative to the portfolio-visibility payoff it's meant to
  buy.
