# Handoff

Start here in a new session. This page says where things stand and what to
do next. It is rewritten at the end of every phase.

Last updated: 2026-11-15, by the planning session.

## How to start a session

1. Read `AGENTS.md`, then this page, then the open phase in
   [Roadmap](roadmap.md).
2. Read the records in [Decisions](decisions.md) that the phase refers to.
3. Check "Waiting on the owner" below. If the open phase needs something
   that is not there yet, ask for it first.
4. Do the phase's "Read first" list before writing anything.

## Where things stand

- **Host preparation: done.** Pool, VNet (10.0.6.0/24), roles, user, the
  token `homelab@pve!tofu` and the Talos image exist ([Host](host.md)).
- **Phase 0 (repository foundation): open.** The planning session made the
  first commit directly on `main`: the rules (`AGENTS.md`, `CLAUDE.md`),
  `docs/`, `.claude/`, `mkdocs.yml`, `README.md`, `.gitignore` and
  `infra/host/prepare.py`. Everything else in phase 0 is still to do,
  through pull requests.
- Nothing of the cluster exists yet. There are no lab VMs.
- Checked and working on 2026-11-15: the Proxmox token (four permission
  paths), the Cloudflare token (zone `savdert.com` only, DNS write), the
  bucket `homelab` (upload, conditional write, delete), write access to
  vault `homelab`.

## What was tested during planning

These results are the basis of decisions D03 to D05. They were produced with
raw API calls, not with OpenTofu.

- A token with the rights in [Host](host.md) can create, resize, start, stop
  and destroy a VM in pool `homelab` and is refused outside it.
- A VM created from `talos-v1.14.6-nocloud-amd64.qcow2` with
  `ipconfig0=ip=<address>/24,gw=<gateway>` and `nameserver=1.1.1.1` came up
  in maintenance mode at that address within two minutes.
  `talosctl get disks --insecure` and `talosctl version --insecure` both
  answered. The test ran on the first subnet (10.0.1.0/24) before the VNet
  was moved to 10.0.6.0/24.
- The agent box (10.0.0.11) reaches the lab subnet through the host. Applying
  SDN changes did not interrupt `vnet0`.
- The parameters of that test VM, for reference when writing `infra/`:
  `machine=q35`, `bios=ovmf`, `efidisk0=local-zfs:1,efitype=4m,pre-enrolled-keys=0`,
  `scsihw=virtio-scsi-pci`,
  `scsi0=local-zfs:0,import-from=local:import/<image>,discard=on,ssd=1`,
  `net0=virtio,bridge=k8s`, `ide2=local-zfs:cloudinit`, `agent=enabled=1`,
  `cpu=host`, then a resize of `scsi0` to 20G.

## Verified in this repository

- `uvx zensical build` builds `docs/` with `mkdocs.yml` without issues
  (2026-11-15, local). The Pages workflow does not exist yet.
- The deny rules in `.claude/settings.json` take effect: after the file was
  written, the session reported the agents `general-purpose`, `Explore`,
  `Plan` and `claude` as no longer available.

## Not verified

- The project agents have not been used yet. Their models and tool lists are
  as written in `.claude/agents/`; confirm with `/agents` in phase 0.
- Everything marked "Prove here" in the roadmap.

## Waiting on the owner

| Needed for | What | State |
|---|---|---|
| Phase 4 | Vault `homelab-cluster`, a read-only service account for it, its token in `op://homelab/eso-service-account/credential`, and a copy of `cloudflare-dns` in the new vault | open |
| Phase 5 | A test from the owner's device (`ping 10.0.6.1`, later the gate commands) | open |
| Phase 7 | An access key limited to bucket `homelab`, in vault `homelab-cluster` as `object-storage` | open |

Everything else the earlier phases need is in place.

### Tailscale

Done on 2026-11-15 and read back with the read-only client in
`op://dotfiles/tailscale-oauth-readonly`: the subnet router advertises and
has enabled 10.0.6.0/24, and the policy lets tailnet members reach it. Not
yet tested: traffic from one of the owner's devices to 10.0.6.0/24.

## Reviews of the design

Two external reads were made before the first commit, on 2026-11-15, and
every finding was checked against the files or by a test before it was
accepted:

- the audit of the first commit (internal auditor and Gemini 4 Hydrogen):
  it replaced the shell version of the host script with
  `infra/host/prepare.py` and tightened the gates;
- a design review by Gemini 4 Argon: it led to D25 (a separate vault for
  the cluster), D26 (Cilium rollout settings), D27 (database parameters),
  the pod security label in phase 6 and several gate changes. Its proposal
  to replace Envoy Gateway with Cilium's Gateway API was not taken; the
  reason is in D21.

## For the architect

- The design is closed. The open work is implementation, the "Decide here"
  items and the "Prove here" items in the roadmap.
- The box cannot read vault `homelab` with its own service account. Tasks
  that need it take the `homelab` token from vault `dotfiles` for that one
  command:
  `OP_SERVICE_ACCOUNT_TOKEN="$(op read op://dotfiles/homelab-op-service-account/credential)" op ...`
  That account can also create items.
- `gh` on the box is `opgh`.
- The first thing to do in phase 0 is the "Read first" list; obenhub is
  checked out at `/home/agent/work/obenhub`.
- The administrator token for Proxmox works from the box. Do not use it for
  anything except `infra/host/prepare.py` on the owner's request.
- VM IDs 201 to 203 and addresses 10.0.6.10 to 10.0.6.13 are reserved.
- When a phase closes: update the state table in the roadmap, write the
  guide page, rewrite this page.
