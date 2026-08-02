# ADR-0009: KSOPS for ArgoCD-native SOPS decryption

Date: 2026-08-02
Status: Accepted

## Context

ADR-0003 chose SOPS + age for secrets at rest and explicitly deferred the
"how does a running cluster consume these" question to Phase 1, once ArgoCD
existed. ADR-0007 picked ArgoCD over Flux despite Flux's native SOPS support,
on the bet that the KSOPS Config Management Plugin (CMP) route was workable
— and flagged it as a gap to resolve "before the ingress/TLS or observability
items land any real credentials." Both of those upcoming items (TLS
certificates, Grafana/Loki credentials) need encrypted secrets synced by
ArgoCD, so this can't be deferred further.

ArgoCD's repo-server renders manifests before they're applied; it has no
built-in SOPS awareness, so a `*.sops.yaml` file synced as-is would apply the
encrypted ciphertext verbatim. `kustomize` supports exec plugins as
generators, which is the extension point KSOPS uses — but that requires the
`ksops` and a plugin-aware `kustomize` binary to actually be present on the
repo-server, since ArgoCD's stock image ships neither.

## Decision

Use **KSOPS** (`viaductoss/ksops`), a `kustomize` exec plugin that shells out
to `sops` to decrypt inline. Integration is the pattern documented upstream
for the `argo-cd` Helm chart — an init container that installs the `ksops`
and `kustomize` binaries from the KSOPS image onto a shared `emptyDir`,
which the `repo-server` container then mounts over its own `/usr/local/bin`
copies — not an ArgoCD Config Management Plugin (CMP) sidecar; KSOPS works
entirely through `kustomize`'s own exec-plugin mechanism, so no separate CMP
process is needed. Concretely, in `gitops/argocd/values.yaml`:

- `configs.cm.kustomize.buildOptions: "--enable-alpha-plugins --enable-exec"`
  — required for ArgoCD's `kustomize build` invocation to honor exec plugins
  at all.
- `repoServer.initContainers`: `install-ksops`, running
  `ksops install --with-kustomize /custom-tools` from the `viaductoss/ksops`
  image into a shared `custom-tools` emptyDir.
- `repoServer.volumeMounts`: overlays `/usr/local/bin/kustomize` and
  `/usr/local/bin/ksops` on the main repo-server container from that
  emptyDir.
- `repoServer.volumes` / `env`: a `sops-age` volume backed by a Kubernetes
  Secret (`sops-age`, key `key.txt`, projected as `keys.txt`) mounted at
  `/.config/sops/age/`, with `SOPS_AGE_KEY_FILE` pointed at it — the same
  age private key ADR-0003 already uses for Terraform, reused rather than a
  second keypair.
- Any manifest needing decryption gets a `kustomization.yaml` with a
  `generators:` entry pointing at a `ksops`-annotated generator resource
  listing the `*.sops.yaml` file(s), per KSOPS's own convention.

The `sops-age` Secret itself is created **imperatively**, once, directly in
the `argocd` namespace (`kubectl create secret generic sops-age
--from-file=key.txt=...`) — never committed to git, per the security
baseline in `CLAUDE.md`. This is a manual bootstrap step analogous to the
day-0 Helm installs for Cilium/ArgoCD themselves (ADR-0006/ADR-0007):
something that must exist before GitOps can rely on it, re-run only if the
cluster is rebuilt or the age key rotates.

## Alternatives considered

- **Flux's native SOPS decryption.** Not applicable — ADR-0007 already
  chose ArgoCD over Flux for portfolio-visibility reasons, accepting this
  integration cost as a known consequence.
- **External Secrets Operator + a hosted secrets backend (Infisical,
  Vault).** Rejected for the same reason ADR-0003 rejected it for Phase 0:
  it's a heavier operational surface (another HA service, another failure
  mode to reason about) than a single-operator homelab's Phase 2 database
  work justifies spending reliability budget on. Revisit if Phase 2's
  cross-namespace secret sprawl (multiple DB operators, backup targets)
  makes SOPS's per-file, no-runtime-service model start to strain.
- **A custom ArgoCD Config Management Plugin (CMP v2 sidecar).** KSOPS
  ships its own dedicated custom-tools-injection recipe for the `argo-cd`
  Helm chart, which is simpler than standing up and maintaining a general
  CMP sidecar just to run `kustomize build`; a CMP would be the right tool
  if the plugin needed to shell out to something other than `kustomize`
  itself, which isn't the case here.
- **A custom ArgoCD container image (build `ksops`/`kustomize` into a
  from-scratch `argoproj/argocd` image, per KSOPS's own Dockerfile
  example).** Rejected — trades a same-pod init container for an
  externally-built and -maintained image, adding a CI/registry surface for
  no behavioral gain at this scale.
- **Decrypt out-of-band and commit rendered plaintext to a separate,
  gitignored overlay.** Rejected outright — defeats the entire point of
  encrypting at rest and reintroduces exactly the "plaintext secret
  somewhere in a directory" risk `CLAUDE.md` rules out.

## Consequences

- Any manifest needing decrypted values must live under a `kustomization.yaml`
  that lists the `.sops.yaml` file as a `ksops` generator input — plain
  `kubectl apply`-style flat YAML won't trigger the plugin. This shapes how
  ingress TLS and observability credentials get structured going forward:
  Kustomize-based, not raw manifests, wherever secrets are involved.
- The `sops-age` Secret is a piece of untracked, manually-created cluster
  state — same category as `~/.config/sops/age/keys.txt` on the operator's
  machine. If the cluster is rebuilt from scratch, this step must be redone
  before any Application referencing encrypted manifests will sync clean;
  documented in `infrastructure/terraform/README.md` alongside the existing
  age-key bootstrap note.
- One age keypair now backs both the Terraform-layer secrets (ADR-0003) and
  the cluster-layer secrets (this ADR) — simpler to operate, but it also
  means rotating the key is a two-surface operation (local
  `~/.config/sops/age/keys.txt` plus the `sops-age` cluster Secret) that has
  to happen together.
- The repo-server Deployment carries an extra sidecar container from here
  on; a small, constant resource cost accepted for the sync-time decryption
  it buys.
