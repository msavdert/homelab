# Handoff

Start here in a new session. This page says where things stand and what to
do next. It is rewritten at the end of every phase.

Last updated: 2026-11-19, phase 12 (alert delivery and dead man's
switch) open, gates 1, 4 and 7 passed, Telegram receiver added.
Phases 0 to 11 are done; 13 to 16 are planned (D46).

## How to start a session

1. Read `AGENTS.md`, then this page, then the open phase in
   [Roadmap](roadmap.md), if one is open. Between phases, AGENTS.md
   ("Between phases") says what may be done.
2. Read the records in [Decisions](decisions.md) that the work refers to.
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
  bootstrap releases were adopted in place. On a new cluster
  `bootstrap:secrets` and `bootstrap:flux` follow `bootstrap:cilium`. helm-controller runs with
  `DisableChartDigestTracking` (D33), without which the first adoption
  restarted every Cilium pod. How, and the gate output:
  [Flux](guide/03-flux.md).
- **Phase 4 (secrets): done 2026-11-15.** External Secrets 2.15.0 reads
  vault `homelab-cluster` with a read-only service account through
  ClusterSecretStore `onepassword` (D25). The token Secret is applied by
  `mise run bootstrap:secrets`, which runs between `bootstrap:cilium` and
  `bootstrap:flux` on a rebuild. `eso-gate` proved the path and
  was removed in phase 5. How, how to add a secret, and the gate output:
  [Secrets](guide/04-secrets.md).
  The read-write token of vault `homelab` was printed into a session log
  during the gate and rotated by the owner the same day.
- **Phase 5 (ingress): done 2026-11-15.** `https://<name>.lab.savdert.com`
  answers on the tailnet: Cilium announces 10.0.6.20 on layer 2 (pool
  10.0.6.20 to 10.0.6.29), Envoy Gateway 1.10.0 terminates TLS with a
  wildcard certificate that cert-manager v1.21.3 issues by DNS-01, and
  `mise run dns:apply` keeps the record `*.lab.savdert.com` in Cloudflare.
  Gateway API CRDs come from the Envoy Gateway chart (D34). The echo
  fixture was removed once Keycloak was served. How it works, how
  to expose a service, and the gate output: [Ingress](guide/05-ingress.md).
- **Phase 6 (storage): done 2026-11-16.** The data disk of each node is
  the Talos user volume `local-path-provisioner` (`/dev/sdb1`, XFS,
  `noexec`) at `/var/mnt/local-path-provisioner`; local-path-provisioner
  0.0.37 keeps volumes there and provides the default StorageClass
  `local-path` (D35). Volumes are bound to their node. How, and the gate
  output: [Storage](guide/06-storage.md).
- **Phase 7 (first database): done 2026-11-16, one follow-up open.** The
  operator, the plugin and cluster `postgres` are defined under
  `kubernetes/apps/cnpg-system/` and `kubernetes/apps/database/` (D36).
  The bucket refuses bulk deletes (`MissingContentMD5`); Barman 3.20.1
  falls back to single deletes, which work, including a retention delete
  with `REDUNDANCY 2` (gate step 6a, D37). How, and the gate output:
  [Database](guide/07-database.md). Follow-up 6b closed on
  2026-11-19 on archive generation 2; retention is `7d`. Every backup
  runs on the primary (D48). The bucket-limited
  key is in vault `homelab-cluster` as `object-storage` (checked
  2026-11-15, see [Architecture](architecture.md), "Secrets").
- **Phase 8 (first application, Keycloak): done 2026-11-17.** The
  Keycloak Operator 26.8.2 from `keycloak-k8s-resources` at the tag (a Flux
  `GitRepository`; CRDs never pruned), cluster `keycloak-db` (two
  instances, backups to `cnpg/keycloak-db/`) and Keycloak at
  `https://keycloak.lab.savdert.com`, all in namespace `keycloak` under
  the restricted pod security level (D38, D39, D40). The bootstrap admin
  is item `keycloak` in vault `homelab-cluster`; Keycloak shows it as a
  temporary admin, which is kept until realms are kept in Git. How, and
  the gate output: [Keycloak](guide/08-keycloak.md).
- **Phase 9 (start page): done 2026-11-17.** Homepage v2.8.0 at
  `https://home.lab.savdert.com` in namespace `homepage` (restricted, read-only
  root file system), signed in by its own OIDC against Keycloak realm
  `lab`, which a `KeycloakRealmImport` creates with client `homepage` and
  user `owner` (D41; items `homepage` and `keycloak-lab-user` in vault
  `homelab-cluster`). Applications appear on the page from annotations on
  their `HTTPRoute`. How, and the gate output:
  [Homepage](guide/09-homepage.md).
- **Phase 10 (monitoring): done 2026-11-17.** victoria-metrics-k8s-stack
  0.98.1 as release `vm` in namespace `observability` (privileged, for
  node-exporter): VMSingle (30 days, 20 GiB), VMAgent, vmalert (with
  Alertmanager since phase 12, D47), kube-state-metrics, node-exporter, and Grafana at
  `https://grafana.lab.savdert.com` with its own OIDC against realm `lab`,
  client `grafana` (D42, D43; item `grafana`). Every CloudNativePG cluster
  is scraped through one `VMPodScrape`. The tool used 933 MiB after start
  and 1310 MiB seven hours later. How, and the gate output:
  [Monitoring](guide/10-monitoring.md).
- Checked and working on 2026-11-15: the Proxmox token (four permission
  paths), the Cloudflare token (zone `savdert.com` only, DNS write), the
  bucket `homelab` (upload, conditional write, delete), write access to
  vault `homelab` and `homelab-cluster`.
- **Phase 11 (rebuild and restore drill): done 2026-11-17.** VMs 201 to
  203 destroyed and rebuilt from Git in 20 minutes; both clusters
  recovered from generation 1 and archive to `postgres-g2` and
  `keycloak-db-g2` (D45). Marker row, realm `lab` with its users and
  clients came back; Cilium was adopted without a restart (D33). The next
  rebuild moves both to generation 3 in one pull request merged after the
  destroy ([Rebuild](guide/11-rebuild.md)).

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
- Phase 5 proofs, on 2026-11-15: the address moved to another node on a
  clean reboot of its holder with no failed request; the owner's Mac
  reached the lab over the tailnet with a valid certificate, and resolved
  the public record with a private address without a DNS override (with
  Tailscale off: `curl` exit 28, not 6). Details in
  [Ingress](guide/05-ingress.md), "Check".
- Phase 6 proof, on 2026-11-16: a volume kept its data across a reboot of
  its node (k8s-3), and deleting the claim removed the PV and its
  directory. The same reboot left 45 failed cilium-operator pods
  (`NodeShutdown`), removed by hand; see [Storage](guide/06-storage.md),
  "When it goes wrong".
- Phase 7 proofs, on 2026-11-16: point-in-time recovery to a time between
  two inserts; a drain of the primary's node promoted a replica and
  `postgres-rw` answered again after about 12 seconds, and after the
  uncordon the drained instance came back on its own node (where its
  local-path volume is; its state during the drain was not recorded); the
  bucket accepts retention deletes through Barman's
  per-object fallback (D37). Details in [Database](guide/07-database.md),
  "Check".
- Phase 7 follow-up 6b, on 2026-11-19: the plugin's own retention removed
  the first backups of archive generation 2 and their WAL and left
  generation 1 alone ([Database](guide/07-database.md), "Check", step 6);
  retention is back to `7d`.
- `kubectl` 1.37.2 against the 1.36.6 cluster: one minor of skew, used
  for the whole gate without problems.

## Not verified

- Failover of the load-balancer address on a hard stop of its holder (lease
  expiry, 15 s by default); only a clean reboot was tested.
- `upgrade-k8s` has not been run for real (only `--dry-run`). That a
  newer installer image than the disk image installs cleanly on a new VM
  (V18) was not tested; both were v1.14.6 in the drill.
- A Renovate pull request for Flux or flux-operator has not arrived yet.
- Renovate updating the `GitRepository` tag of the Keycloak Operator; the
  flux manager documents it, but no pull request has arrived yet.
- Behaviour of the bootstrap admin when item `keycloak` changes (believed
  not to apply, see the Keycloak guide).
- Rotating the client secret of `homepage` or `grafana` (Homepage and
  Monitoring guides, "Day-two tasks").
- The memory of the monitoring tool after days of data; only the first
  seven hours were measured (Monitoring guide, "Day-two tasks").
- etcd, scheduler and controller manager metrics on Talos (not scraped,
  D42).

## Waiting on the owner

| Needed for | What | State |
|---|---|---|
| Phase 7 | An access key limited to bucket `homelab`, in vault `homelab-cluster` as `object-storage` | done 2026-11-15 |
| Phase 8 | The name of the first application | done 2026-11-16: Keycloak |
| Next phase | Which comes first: the start page or monitoring | done 2026-11-17: the start page (D41) |
| Phase 9 | Login method, realm user name, 1Password items | done 2026-11-17: Homepage OIDC, user `owner`, items approved |
| Phase 10 | Nothing; the owner left the tool and the login to the architect (D42, D43) | done 2026-11-17 |

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

- Phases 0 to 11 are done; phase 12 is open (roadmap); 13 to 16 are planned (D46). Between phases,
  maintenance follows the "Between phases" rule in AGENTS.md; work with a
  live gate of its own opens a new phase.
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
- Every application with PostgreSQL gets its own CloudNativePG cluster
  `<app>-db` in its namespace (D39); extract a shared Flux component when
  the second one arrives, not before.
- Keycloak admin tasks: pipe the login lines from the Keycloak guide
  (check step 3) and `kcadm.sh` commands into
  `kubectl -n keycloak exec -i keycloak-0 -- sh`; the credentials come from
  the pod's environment, not from the box.
- A new application goes on the start page through `gethomepage.dev/*`
  annotations on its `HTTPRoute` (Homepage guide, step 3); a realm or
  client for it goes into a `KeycloakRealmImport` (D41).
- A Renovate bump of Homepage: list `/app/src/skeleton` in the new image
  first; every file there needs a ConfigMap entry and a mount, or the pod
  crashes after login (Homepage guide, "Day-two tasks").
- Grafana: `https://grafana.lab.savdert.com`; queries from the box go to
  VMSingle through `kubectl -n observability port-forward svc/vmsingle-vm
  8428`. A new application is scraped with a `VMServiceScrape` or
  `VMPodScrape`, not a `ServiceMonitor` (D42). OpenTelemetry metrics can go
  to `/opentelemetry/v1/metrics` on VMSingle once a collector is decided.
- A subagent that runs `kind` from inside the clone writes into the
  clone's `kubeconfig`; give it its own `KUBECONFIG` (Monitoring guide,
  "When it goes wrong").
- Phase 12, alert delivery and dead man's switch, is open (2026-11-19).
  Done: D47 (#63); check `homelab-watchdog` on healthchecks.io (300 s
  period, 300 s grace, the two channels of `perp-live-loop`) and item
  `alertmanager` with field `watchdog-url`, created by a one-off script
  whose plan is in #63; Alertmanager with the Watchdog route (#64).
  Passed on 2026-11-19: gate 1 (pods ready, no `blackhole`, notifier is
  `vmalertmanager-vm-0`); gate 4 (vmalert stopped 03:06:42 UTC by
  `flux suspend hr`, `paused: true` on VMAlert, scale to 0, and the
  operator left it at 0; flips down 03:17:57, up 03:18:17 after the
  undo; whether the owner received the email or Bark is to be asked);
  gate 7 (1215 MiB, Alertmanager 25 MiB). Healthchecks.io takes
  Alertmanager's POST (first ping 03:05:57, `webhook` counter 1).
  The owner received the gate 4 alarm. The lab's bot
  (`@homelab_846_bot`, item `telegram-bot-homelab` in vault `homelab`)
  sends every alert of severity above `info` to the owner's chat; the
  token and chat id are in item `alertmanager` (#66). Next: gates 2, 3,
  5 and 6. Known gap: Alertmanager replaces a Telegram message over 4096
  characters with a placeholder (HTML mode); a group of many alerts can
  hit it (audit of #66).
  Planned after it: 13 backup and database alerts, 14 Proxmox host and ZFS, 15
  logs, 16 control plane metrics ([Roadmap](roadmap.md)). The lab's
  monitoring does not depend on the owner's `obenhub`; obenhub may read
  this cluster later, as its own work (D46). The Telegram bot of phase 12
  exists (`@homelab_846_bot`).
- When a phase closes: update the state table in the roadmap, write the
  guide page, bring `README.md`, `docs/index.md` and
  `docs/architecture.md` up to date, rewrite this page.
