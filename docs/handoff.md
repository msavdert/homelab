# Handoff

Start here in a new session. This page says where things stand and what to
do next. It is rewritten at the end of every phase.

Last updated: 2026-11-15, when phase 3 closed.

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
- **Phase 0 (repository foundation): done 2026-11-15.** Tool pins and
  `mise run check`, the four workflows, release-please, the docs site on
  Pages, the `main` ruleset and Renovate are in place; how they fit is in
  [Repository](guide/00-repository.md). Released as `v0.1.0`.
- **Phase 1 (nodes): done 2026-11-15.** VMs 201 to 203 (`k8s-1` to
  `k8s-3`) run Talos v1.14.6 in maintenance mode at 10.0.6.11 to
  10.0.6.13, created by OpenTofu from `infra/`; state is encrypted in
  bucket `homelab` under `tofu/`. How, and the gate output:
  [Nodes](guide/01-nodes.md). The VMs have no Proxmox tags (D28).
- **Phase 2 (cluster): done 2026-11-15.** Kubernetes 1.36.6 (D29) on the
  three nodes, Cilium 1.20.4 replacing kube-proxy, API at the virtual IP
  10.0.6.10. Configuration from `talos/`, secrets in item `talos` (one
  field, D30), installer `nocloud-installer` (D31). Cilium was installed
  with `mise run bootstrap:cilium` from
  `kubernetes/apps/kube-system/cilium/app/`. How, and the gate output:
  [Cluster](guide/02-cluster.md).
- **Phase 3 (Flux): done 2026-11-15.** Flux 2.10.0 through the Flux
  Operator 0.62.1 reconciles `kubernetes/apps/` from `main` every minute.
  Cilium, flux-operator and the FluxInstance are managed by Flux; the
  bootstrap releases were adopted in place. `bootstrap:flux` follows
  `bootstrap:cilium` on a new cluster. helm-controller runs with
  `DisableChartDigestTracking` (D33), without which the first adoption
  restarted every Cilium pod. How, and the gate output:
  [Flux](guide/03-flux.md).
- **Phase 4 (secrets): open.** Nothing built. It needs the owner's items
  below first.
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

- The phase 0 gate, on 2026-11-15: output in
  [Repository](guide/00-repository.md), "Check".
- The deny rules in `.claude/settings.json` take effect: after the file was
  written, the session reported the agents `general-purpose`, `Explore`,
  `Plan` and `claude` as no longer available.
- The project agents `researcher` and `auditor` were used in phase 0 and
  returned usable results. `executor`, `locate` and `grunt` have not been
  used yet.
- Phase 1 proofs, on 2026-11-15: the `s3` backend lock refuses a second
  run (HTTP 412) with `skip_s3_checksum` alone; the stored state is an
  encrypted envelope; a fresh clone plans no changes. Details in
  [Nodes](guide/01-nodes.md), "Check".
- The QEMU guest agent answers in maintenance mode (Proxmox
  `agent/network-get-interfaces` on all three VMs).
- Phase 2 proofs, on 2026-11-15: the `nocloud` image keeps its address
  and hostname after the configuration is applied and after an upgrade;
  the virtual IP moves on a clean reboot with no failed request and on a
  hard stop of its holder after about 61 seconds; workload isolation does
  not keep pods off control planes; `talosctl upgrade` to the same
  version with the factory installer works. Details in
  [Cluster](guide/02-cluster.md), "Check".
- Phase 3 proofs, on 2026-11-15: a Flux Helm upgrade of `cilium` with
  unchanged inputs replaces no pod once D33 is in force; a merged value
  change reaches the cluster in seconds with nothing run by hand. Details
  in [Flux](guide/03-flux.md), "Check". Renovate lists the flux-operator
  chart and `fluxcd/flux2` in `fluxinstance.yaml` in issue #6.
- `kubectl` 1.37.2 against the 1.36.6 cluster: one minor of skew, used
  for the whole gate without problems.

## Not verified

- Everything marked "Prove here" in the roadmap from phase 4 on.
- Rebuilding the cluster from nothing (Cluster and Flux guides, "Day-two
  tasks") and `upgrade-k8s` have not been run. A fresh adoption of Cilium
  with D33 in force from the start was shown only through the equivalent
  forced upgrade, and for flux-operator on a kind cluster.
- A Renovate pull request for Flux or flux-operator has not arrived yet.

## Waiting on the owner

| Needed for | What | State |
|---|---|---|
| Phase 4 | Vault `homelab-cluster`, a read-only service account for it, its token in `op://homelab/eso-service-account/credential`, and a copy of `cloudflare-dns` in the new vault | open |
| Phase 5 | The gate commands run from the owner's device when the phase reaches its gate | open |
| Phase 7 | An access key limited to bucket `homelab`, in vault `homelab-cluster` as `object-storage` | open |

Everything else the earlier phases need is in place.

### Tailscale

Done on 2026-11-15 and read back with the read-only client in
`op://dotfiles/tailscale-oauth-readonly`: the subnet router advertises and
has enabled 10.0.6.0/24, and the policy lets tailnet members reach it. The
owner's laptop reached 10.0.6.1 over the tailnet on 2026-11-15 (`ping`, no
loss, about 95 ms).

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
- Start of every session: Dependency Dashboard (issue #6) and the open
  Renovate pull requests (D23). Minor and major updates of `talosctl`,
  `kubectl`, `flux2` and `cilium-cli` arrive labelled `upgrade-drill`.
- The box cannot read vault `homelab` with its own service account. Tasks
  that need it take the `homelab` token from vault `dotfiles` for that one
  command:
  `OP_SERVICE_ACCOUNT_TOKEN="$(op read op://dotfiles/homelab-op-service-account/credential)" op ...`
  That account can also create items.
- `gh` on the box is `opgh`.
- The administrator token for Proxmox works from the box. Do not use it for
  anything except `infra/host/prepare.py` on the owner's request.
- VM IDs 201 to 203 and addresses 10.0.6.11 to 10.0.6.13 are in use by the
  nodes; 10.0.6.10 is the API virtual IP (D07).
- Cluster access: `mise run talos:config` and `mise run talos:kubeconfig`
  write `talosconfig` and `kubeconfig` into the clone (gitignored, D30);
  `mise.toml` points `TALOSCONFIG` and `KUBECONFIG` at them. A shell
  without mise's environment (such as the agent's Bash tool) has to
  export them.
- The machine-wide mise task `kube:homelab` (from the workbench, "pull
  kubeconfig + talosconfig from 1Password into ~/.kube and ~/.talos") is
  not part of this repository and is not used; D30 regenerates instead.
- OpenTofu: `mise run infra:plan`, `infra:apply`, `infra:pool`. The token
  cannot set Proxmox tags at VM creation (D28).
- The Bash tool has no mise environment: export `KUBECONFIG` and put the
  tools on `PATH` (`export PATH="$(dirname "$(mise which flux)"):$PATH"`).
  `mise exec` always uses the clone's `kubeconfig`, whatever is exported.
- From phase 3 on, the cluster changes through merged pull requests. Do
  not `helm upgrade` a Flux-owned release by hand; it fails on field
  conflicts (Flux guide, "When it goes wrong").
- When a phase closes: update the state table in the roadmap, write the
  guide page, rewrite this page.
