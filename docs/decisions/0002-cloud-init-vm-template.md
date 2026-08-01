# ADR-0002: Cloud-init base image via Terraform-managed VM template

Date: 2026-08-01
Status: Accepted

## Context

Phase 0 needs a repeatable way to provision the base OS for VMs (and later
CTs) on Proxmox, driven by Terraform rather than manual ISO installs. Two
common approaches exist in the Proxmox ecosystem: hand-build a customized
template with Packer, or import a vendor-published cloud-init-enabled cloud
image and clone it per VM with per-instance cloud-init config.

At this stage nothing is baked into the base image yet — no agents, no
custom packages, no hardening beyond what the distro ships. The
distinguishing needs are: fast iteration while the platform is still being
designed, and full config transparency in git (cloud-init user-data is
plain YAML, readable in a diff).

## Decision

Use the official Debian 12 ("bookworm") generic cloud image
(`debian-12-generic-amd64.qcow2`) as the base. Terraform (via the
`bpg/proxmox` provider) downloads the image into Proxmox storage, converts
it into a VM template with the qemu-guest-agent and cloud-init drive
enabled, and every provisioned VM is a Terraform-managed **clone** of that
template with per-VM cloud-init user-data (hostname, SSH keys, static
Tailscale-reachable networking where needed).

Debian is chosen over Ubuntu for a smaller base footprint and longer
predictable release cadence; either would have worked equally well for this
project's purposes.

## Alternatives considered

- **Packer-built custom template** (bake packages/hardening into the image
  at build time). Rejected for now — adds a build pipeline before there is
  anything non-trivial to bake in. Revisit once the base config that every
  VM needs (e.g. common monitoring agent, hardening baseline) stabilizes
  enough that re-running cloud-init on every clone becomes wasteful or
  slow. If that happens, it supersedes this ADR.
- **Manual ISO install per VM.** Rejected — not code-provisioned, fails the
  "Terraform for VM/CT lifecycle" ground rule in `CLAUDE.md`.
- **LXC containers as the default instead of VMs.** Not rejected outright,
  but not the default — CTs remain an option per-workload (e.g. lightweight
  tooling) decided in Phase 2, not a Phase 0 platform-wide choice.

## Addendum (2026-08-01): image staging done out-of-band

The `proxmox_download_file` Terraform resource (which would have downloaded
the image via the Proxmox API's `query-url-metadata`/`download-url`
endpoints) fails with a bare "Permission check failed" when called via an
API token, even one holding the exact permission (`Sys.Audit` at `/`) that
endpoint's own source declares sufficient — reproduced directly against the
raw API with `curl`, so not a Terraform provider bug. Ticket-based auth
isn't available either, since the least-privilege `terraform@pve` user
(ADR-0003) is a token-only PVE-realm account with no password.

Worked around by staging the qcow2 once by hand: `ssh root@pve wget ...`
into the `local` storage's `import` content path. Terraform still owns
creating the VM template *from* that staged file (`import_from` points at
the resulting volume ID) — only the download step itself is manual. See
`infrastructure/terraform/image.tf` for the full explanation and the exact
command used. Revisit `proxmox_download_file` if a future Proxmox VE point
release fixes token auth for that endpoint.

## Consequences

- Every VM's OS-level config is visible as cloud-init user-data in git —
  directly serves the "documentation is the deliverable" goal.
- Template rebuilds (e.g. picking up a new Debian point release) are a
  Terraform re-apply of the image-download resource, not a manual process.
- Cloud-init reruns on every clone, which is slightly slower boot than a
  fully pre-baked Packer image — acceptable tradeoff at current scale
  (single host, low VM count).
