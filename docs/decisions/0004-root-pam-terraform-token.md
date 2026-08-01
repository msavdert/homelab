# ADR-0004: Terraform authenticates as `root@pam`, superseding the scoped `terraform@pve` token

Date: 2026-08-01
Status: Accepted — supersedes the token-scoping part of ADR-0003

## Context

ADR-0002's implementation hit a wall: Proxmox VE 9.2.5's
`/nodes/{node}/query-url-metadata` endpoint (used by
`proxmox_download_file` to fetch the cloud image server-side) rejected the
least-privilege `terraform@pve` API token with a bare "Permission check
failed" — reproduced directly against the raw API with `curl`, confirming
it wasn't a Terraform provider bug, even though the token held exactly the
permission (`Sys.Audit` at `/`) the endpoint's own source
(`PVE::API2::Nodes::query_url_metadata`) declares sufficient.

Reading `/usr/share/perl5/PVE/RPCEnvironment.pm::check_api2_permissions`
on the host explains why:

```perl
return 1 if $username eq 'root@pam';
raise_perm_exc('user != root@pam') if !$perm;
```

Permission checks for **any** non-`root@pam` identity fall through to the
route's declared ACL check — which should have passed for `terraform@pve`
given its granted `Sys.Audit`, but evidently doesn't for this specific
route in this PVE version (undetermined further root cause, possibly a
second, undocumented restriction on token auth for URL-fetching routes,
likely SSRF-motivated). `root@pam` is hardcoded to bypass permission
checking entirely, before any ACL is evaluated.

**Confirmed by direct testing that this bypass alone is not sufficient —
API token privilege separation (`privsep`) also matters.** A `root@pam`
token created with the `pveum` default (`--privsep 1`) still got the same
403; Proxmox's token auth resolves `privsep=1` tokens to their own
token-scoped identity (`root@pam!tokenid`) for permission purposes, which
does **not** string-match the hardcoded `eq 'root@pam'` check. Recreating
the token with `--privsep 0` (token inherits the user's identity/
permissions directly, no separate ACL) made the bypass apply and the
download succeeded. Both conditions are required: `root@pam` as the user,
**and** `privsep=0` on the token.

The initial workaround (ADR-0002 addendum) staged the image with a manual
`ssh root@pve wget ...` step. The operator explicitly rejected manual
bootstrap steps as an ongoing pattern — this repo's provisioning must be
fully autonomous end-to-end, and a prior project (`homelab_backup`)
already established that a `root@pam` token sidesteps this exact class of
problem for Talos ISO downloads via the same `proxmox_download_file`
resource.

## Decision

Terraform authenticates to the Proxmox API as a `root@pam` API token
(dedicated token, not the interactive root session) instead of the
scoped `terraform@pve` PVE-realm user from ADR-0003. This restores full
automation: `proxmox_download_file` downloads the cloud image directly,
no manual staging step, no undocumented one-off host access.

The `terraform@pve` user and `TerraformProv` role from ADR-0003 are
removed — a partially-working least-privilege setup that still requires
manual intervention isn't a real security win, it's a security placebo
with an operational cost. This is a conscious trade of defense-in-depth
(a compromised Terraform credential now has full API access) for
automation reliability, judged acceptable because:

- The Proxmox API is reachable only over Tailscale (`CLAUDE.md`'s
  "no public SSH exposure" rule extends in spirit to the API — it was
  never exposed publicly either).
- The credential lives encrypted (SOPS + age, ADR-0003's actual
  contribution — encryption at rest — is unaffected by this ADR) and is
  decrypted only transiently into the Terraform process environment.
- The single-operator, single-host nature of this project means the
  blast radius of a compromised token is the same host the operator
  already has root SSH access to — it doesn't cross a trust boundary
  that didn't already exist.

## Alternatives considered

- **Keep debugging the PVE-side permission bug.** Rejected for now — no
  further leads without either patching PVE's Perl source (out of scope,
  fragile across upgrades) or filing/waiting on an upstream bug report,
  neither of which unblocks Phase 0 today. Revisit if a future PVE
  release changes this behavior; would let ADR-0003's original
  least-privilege token come back.
- **Keep the manual `wget` staging step permanently.** Rejected — explicit
  operator preference for full automation over defense-in-depth here;
  a recurring manual step also silently breaks reproducibility (a fresh
  `terraform apply` on a rebuilt host would fail the same way until
  someone remembers the undocumented-in-code manual step).
- **Proxmox-side SSH-key/local automation user instead of an API token.**
  Not evaluated in depth — would trade one auth mechanism's rough edges
  for another's, without solving the root cause; API tokens are the
  Terraform-idiomatic mechanism for this provider.

## Consequences

- `image.tf`/`template.tf` revert to the ADR-0002-original design:
  `proxmox_download_file` owns the download, no manual steps, `terraform
  apply` alone is sufficient to (re)build the template from scratch.
- The `terraform@pve` user, `TerraformProv` role, and its token are
  deleted from the Proxmox host — no unused, undocumented credentials left
  behind.
- `infrastructure/terraform/README.md`'s token-bootstrap section is
  rewritten to describe the `root@pam` token instead.
- Any future Phase 2+ credential (database backup destinations, TLS
  material) should still default to least-privilege — this ADR is scoped
  specifically to the Terraform-to-Proxmox-API relationship, not a
  blanket policy change.
