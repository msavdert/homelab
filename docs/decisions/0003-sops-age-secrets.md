# ADR-0003: SOPS + age for secrets management

Date: 2026-08-01
Status: Accepted

## Context

`CLAUDE.md` requires a secrets backend from the start — no plaintext
credentials, no `.tfvars`/`.tfstate` containing them, ever committed. Phase
0 needs this wired in before Terraform touches anything credential-shaped
(Proxmox API token, VM root/SSH material). Critically, Phase 0 predates any
running Kubernetes cluster, so a backend that depends on a deployed service
(Vault server, Infisical instance, External Secrets Operator) creates a
chicken-and-egg problem: nothing can bootstrap the platform because the
platform is what would host the secrets store.

## Decision

Use **SOPS** (Mozilla) with an **age** key pair for encryption at rest.
Secrets live in the repo as `*.sops.yaml`/`*.sops.tfvars.json` files,
encrypted — safe to commit, diffable at the structure level (SOPS preserves
keys in the cleartext diff, only values are encrypted). The age private key
lives only on the operator's local machine (`~/.config/sops/age/keys.txt`
or equivalent), never in git, and is what Terraform/`sops exec-env`
decrypts with locally at apply time.

This is a decision for Phase 0 and the Terraform layer specifically.
Phase 1 (Kubernetes) may layer a cluster-native secrets flow (e.g. SOPS +
Flux/ArgoCD SOPS integration, or graduating to External Secrets +
Infisical once there's a cluster to host it) on top — that will get its own
ADR when Phase 1 secrets needs are concrete, and may supersede or extend
this one rather than replace it outright.

## Alternatives considered

- **Infisical / External Secrets Operator** (used in the prior
  `homelab_backup` project). Rejected for Phase 0 — requires a running
  service to bootstrap against, which doesn't exist yet at the
  infrastructure-provisioning stage. Reconsider explicitly in Phase 1 once
  a cluster exists.
- **HashiCorp Vault.** Rejected — operationally heavy (its own HA, unseal,
  storage backend concerns) for a single-operator homelab; the reliability
  investment is better spent on the databases this project is actually
  about, not on securing the secrets manager.
- **`.tfvars` files, gitignored only (never encrypted).** Rejected — no
  protection if the ignore rule is ever misconfigured or the file is
  force-added by mistake; fails the "never commit plaintext secrets" rule
  even as a transient risk. Also not portable across machines without
  out-of-band file transfer.

## Consequences

- Terraform variable files containing secrets are `*.sops.tfvars.json`,
  decrypted just-in-time via `sops exec-env` or the Terraform SOPS
  provider, never written to disk unencrypted.
- Every operator machine that runs `terraform apply` needs the age private
  key provisioned locally (out of band, not via this repo) — a manual
  bootstrap step, documented in `infrastructure/terraform/README.md` when
  that directory is created.
- `.sops.yaml` (the SOPS config mapping which age public key encrypts
  what) is itself committed — it contains only public key material.
