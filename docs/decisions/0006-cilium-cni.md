# ADR-0006: Cilium as the cluster CNI

Date: 2026-08-02
Status: Accepted

## Context

ADR-0005 fixed the Kubernetes distribution as k3s on Debian 12 VMs. k3s
ships Flannel as its default CNI with no network-policy engine and no
built-in traffic observability. The next open Phase 1 item is the CNI
choice itself.

Two realistic options: keep k3s's default (Flannel), or replace it with
Cilium (eBPF dataplane, kube-proxy replacement, Hubble flow/L7
observability, network policy enforcement).

The same tie-breaker from ADR-0005 applies: prefer whatever most directly
serves Phase 2's DBRE work (Postgres/MySQL HA, failover, replication)
over Kubernetes-platform elegance for its own sake. Unlike Talos's
storage-operator friction (ADR-0005), Cilium's main differentiator —
Hubble's per-flow, L7-aware traffic visibility — is plausibly *useful*
for DBRE work: watching connection resets, replication traffic between
Postgres/MySQL pods, and latency between StatefulSet replicas at the
network layer is a real diagnostic tool for failover and replication-lag
incidents, not just platform polish.

## Decision

Run **Cilium** as the cluster CNI, replacing k3s's default Flannel and
kube-proxy.

k3s is installed with `--flannel-backend=none --disable-network-policy
--disable-kube-proxy`, and Cilium is installed separately via Helm with
`kubeProxyReplacement=true` (and `operator.replicas=1` while the cluster
is single-node, since the operator's default anti-affinity assumes
multiple nodes).

This is accepted as a **day-0 bootstrap step, not a GitOps-managed one**:
the GitOps controller (ArgoCD or Flux — still an open Phase 1 item) runs
as pods, and pods cannot be scheduled with an IP until the CNI is
already functioning. So the very first Cilium install has to happen
outside GitOps, via Helm CLI (or Terraform, TBD alongside the
provisioning story) against the freshly bootstrapped cluster.

Once the GitOps controller is running, Cilium's ongoing lifecycle
(version upgrades, config changes) moves under its management like any
other component — a Flux `HelmRelease` or an ArgoCD `Application`
pointing at the Cilium Helm chart. The GitOps tool ADR should account
for this "day-0 manual bootstrap, day-2 GitOps-managed" split explicitly
when it's written.

## Alternatives considered

- **Flannel (k3s default).** Rejected, but not by a wide margin — it is
  genuinely the lower-complexity, lower-overhead choice, and "leave the
  default alone" is consistent with ADR-0005's spirit of not spending
  K8s-learning budget on platform elegance. It loses out here because it
  offers no network-policy engine and no traffic observability at all;
  Hubble's flow visibility has a direct, non-cosmetic use case for
  diagnosing DB network behavior in Phase 2, which tips the tie-breaker
  the other way this time.
- **Calico.** Not seriously evaluated — sits between Flannel and Cilium
  in both capability and complexity without a standout feature that
  serves the DBRE goal better than Cilium's Hubble observability does.

## Consequences

- k3s is installed with Flannel, the built-in network-policy controller,
  and kube-proxy all disabled; Cilium (Helm) is the sole CNI and
  kube-proxy replacement.
- Cilium's initial install is a manual, documented day-0 bootstrap step,
  separate from whatever GitOps tool is chosen later; that tool's ADR
  must describe how Cilium's ongoing config is handed off to it.
- Single-node Cilium operator is deployed with `replicas=1`; revisit
  this setting if/when the cluster grows to multiple nodes.
- Hubble should be enabled and is expected to be used as a diagnostic
  tool during Phase 2 failover/replication-lag drills, not just left
  installed unused — if it turns out not to get used that way, that's a
  signal Flannel would have been the more honest choice in hindsight.
