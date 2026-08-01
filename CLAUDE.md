# CLAUDE.md

Ground rules for AI-assisted work in this repository. Read this before
making changes.

## What this project is

A from-scratch homelab built as a **Database Reliability Engineering (DBRE)
portfolio project** for a career transition. Kubernetes/GitOps is a real,
secondary learning goal, but it is the delivery mechanism — the databases and
their reliability characteristics (HA, backup/restore, failover, monitoring,
runbooks) are the point. When a design choice trades off platform elegance
against database-reliability clarity, prefer the latter.

Full context and current phase: [`docs/PLAN.md`](docs/PLAN.md). Reasoning
behind past decisions: [`docs/decisions/`](docs/decisions/).

## Language

Every artifact committed to this repo — code, comments, commit messages,
docs, READMEs, runbooks — is **English only**, regardless of what language
the conversation with the operator happens in.

## Documentation is not optional

This repo exists to be read by someone evaluating DBRE skill. Any
non-trivial infrastructure or architecture decision gets an ADR in
`docs/decisions/` covering **what** was chosen and **why**, including
rejected alternatives when relevant. "The code is the documentation" is not
sufficient here — the reasoning is the deliverable.

## Infrastructure facts

- Host: Hetzner dedicated, 12 CPU / 128 GB RAM, Proxmox VE 9 on a ZFS mirror
  root (`rpool`, 2× NVMe).
- Reach the Proxmox host over Tailscale as `root@pve` — there is no public
  SSH exposure. Do not add one.
- Provisioning is code-first: Terraform for VM/CT lifecycle against the
  Proxmox API, not manual clicks in the UI. If something was created by
  hand for a one-off experiment, say so explicitly and don't let it linger
  undocumented.
- Storage capacity is generous (1.84 TB ZFS pool, currently ~9 GB used) —
  don't over-optimize disk footprint at the cost of clarity, but do use ZFS
  snapshots deliberately as part of backup/restore design, not just as a
  safety net.

## Security baseline

- Never commit plaintext secrets, credentials, or `.tfstate`/`.tfvars` files
  containing them. Use a secrets backend (design TBD, see ADRs) from the
  start, not as a retrofit.
- Container images: pin to specific versions, never `:latest` — this repo
  will use Renovate (or equivalent) for update PRs, which requires resolvable
  version tags.
- Database credentials, backup destinations, and TLS material follow the
  same rule: reference them via the secrets backend, never inline.

## Token budget / agent delegation

The operator is on a constrained Claude Pro plan. The global Claude Code
setup (`~/.claude/`) already runs `opusplan` (Opus for planning, Sonnet for
execution) with dedicated `Explore` (haiku, read-only search), `grunt`
(haiku, mechanical work), and `builder` (sonnet, implementation) agents.

- Reasoning about architecture, ADRs, and design tradeoffs happens on the
  main model — that's the point of Opus-for-planning.
- Delegate mechanical work (running `terraform plan`/`apply` and reporting
  output, applying a rename across manifests, formatting, collecting
  `kubectl`/`qm`/`pct` output) to `grunt` or `builder` rather than doing it
  inline, and to keep the main conversation's context lean.
- Keep delegated reports tight — conclusions and diffs, not raw log dumps.
- Don't spawn wide parallel agent fan-outs without flagging the likely cost
  first.

## Working with the live server

Proxmox and any provisioned VMs/CTs are real, running infrastructure, not a
sandbox that resets. Before destructive operations (`qm destroy`, `pct
destroy`, `zfs destroy`, force-pushing Terraform state changes that would
recreate resources), confirm with the operator unless a prior instruction in
the current task already authorized it. Prefer `terraform plan` before
`apply`, and show the plan when the change is non-trivial.
