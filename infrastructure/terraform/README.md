# infrastructure/terraform

Terraform against the Proxmox API (`bpg/proxmox` provider). Phase 0's
code-provisioned Debian 12 cloud-init VM template plus Phase 1's k3s
cluster VM, fully automated end to end. Design decisions:
[ADR-0002](../../docs/decisions/0002-cloud-init-vm-template.md)
(image/template strategy), [ADR-0003](../../docs/decisions/0003-sops-age-secrets.md)
(SOPS + age secrets), [ADR-0004](../../docs/decisions/0004-root-pam-terraform-token.md)
(why Terraform authenticates as `root@pam`), and
[ADR-0008](../../docs/decisions/0008-k3snet-private-sdn-network.md) (the
private, NAT-isolated `k3snet` SDN network cluster VMs attach to).

## What's here

| File              | Purpose                                                         |
| ----------------- | ---------------------------------------------------------------- |
| `versions.tf`     | Provider/Terraform version pins                                  |
| `providers.tf`    | Proxmox provider configuration                                   |
| `variables.tf`    | Inputs, with defaults matching the live `pve` host                |
| `image.tf`        | Downloads the Debian 12 cloud qcow2 into Proxmox storage `local`  |
| `template.tf`     | Builds the cloud-init VM template on storage `local-zfs`          |
| `network.tf`      | The `localnat` SDN zone + `k3snet` VNet/subnet cluster VMs attach to (ADR-0008) |
| `k3s_node.tf`      | The single k3s cluster node — a full clone of the template, attached to `k3snet` |
| `outputs.tf`      | Exposes the template VM ID/name for later modules to clone from   |
| `secrets.sops.tfvars.json` | SOPS-encrypted Proxmox API token + endpoint (committed, encrypted) |

## One-time local bootstrap

This module needs `terraform`, `sops`, and `age`, pinned in the repo root's
[`.mise.toml`](../../.mise.toml). Install them with [mise](https://mise.jdx.dev/):

```sh
mise install
```

The age private key is stored in the **1Password `homelab` vault, item
`sops-age-key`, field `private key`** — it never leaves that vault or goes
in git. On a new machine that already has an authenticated `op` CLI
(service account or otherwise):

```sh
mkdir -p ~/.config/sops/age && chmod 700 ~/.config/sops/age
op item get sops-age-key --vault homelab --fields "private key" --reveal \
  | sed -e 's/^"//' -e 's/"$//' > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

(The `sed` strips quoting `op` adds around multiline field values — without
it, `sops` fails to parse the identity file.)

If `op` isn't available/authenticated, fall back to generating a fresh
keypair (`age-keygen -o ~/.config/sops/age/keys.txt`) and re-encrypting
`secrets.sops.tfvars.json` under the new public key — but prefer reusing the
vault copy so old encrypted files stay decryptable.

## Proxmox API token bootstrap (already done once, documented here for reference)

Terraform authenticates as `root@pam` — see
[ADR-0004](../../docs/decisions/0004-root-pam-terraform-token.md) for why a
least-privilege `terraform@pve` user was tried first and abandoned: Proxmox
VE 9.2.5's `query-url-metadata`/`download-url` endpoints (needed for
`proxmox_download_file`) reject any non-`root@pam` identity with a bare
"Permission check failed" regardless of granted ACLs. This was provisioned
once, directly on the host over `ssh root@pve`:

```sh
pveum user token add root@pam terraform-provider --privsep 0 \
  --comment 'infrastructure/terraform bpg/proxmox provider token (ADR-0004)'
```

- **User**: `root@pam` — required for Proxmox's hardcoded permission-check
  bypass (`check_api2_permissions` in `PVE::RPCEnvironment`) to apply at
  all; no scoped-role alternative was found to work for the image-download
  endpoints in this PVE version.
- **`--privsep 0` is required, not optional**: the `pveum` default
  (`--privsep 1`) still fails, because Proxmox resolves a privsep-enabled
  token to its own token-scoped identity (`root@pam!tokenid`) for
  permission purposes, which does not match the hardcoded `eq 'root@pam'`
  check. Only `--privsep 0` (token inherits the user's identity directly)
  makes the bypass apply.
- This trades defense-in-depth for full automation — see ADR-0004's
  Consequences section for the reasoning and the accepted risk. The token
  secret is shown exactly once at creation time; it was captured
  immediately and encrypted (see below), never stored in shell history or
  plaintext on disk.

If this ever needs to be redone (token rotated, host rebuilt), regenerate
with the same command and re-encrypt as described next.

### Encrypting the token

```sh
cat > /tmp/secrets_plain.json <<'EOF'
{
  "proxmox_api_token": "root@pam!terraform-provider=<token-secret>",
  "proxmox_endpoint": "https://pve:8006/"
}
EOF
sops --config ../../.sops.yaml --filename-override secrets.sops.tfvars.json \
  -e --output-type json --input-type json /tmp/secrets_plain.json \
  > secrets.sops.tfvars.json
rm -f /tmp/secrets_plain.json
```

(`--filename-override` is needed because `sops`'s creation-rule matching in
`.sops.yaml` is filename-pattern based, and the plaintext source file here
lives outside that pattern.)

## Cloud-init snippet bootstrap (already done once, documented here for reference)

`k3s_node.tf`'s `initialization.user_data_file_id` points at
`local:snippets/k3s-node-cloud-init.yaml` on the `pve` host — a file placed
manually rather than through `proxmox_virtual_environment_file`. That
resource uploads snippet content over a raw SSH connection to the node's
*public* IP using Go's SSH client, which needs a locally-loaded key/agent
this environment doesn't have (the `ssh root@pve` access used everywhere
else in this repo goes through Tailscale, a separate mechanism the
provider's uploader doesn't use). Provisioned once, directly on the host:

```sh
mkdir -p /var/lib/vz/snippets
cat > /var/lib/vz/snippets/k3s-node-cloud-init.yaml <<'EOF'
#cloud-config
hostname: k3s-node-01
manage_etc_hosts: true
users:
  - name: k3sadmin
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - <var.k3s_ssh_public_key value, from variables.tf>
packages:
  - qemu-guest-agent
runcmd:
  - systemctl enable --now qemu-guest-agent
EOF
```

Also required once, host-side: the `local` storage's content types didn't
include `snippets` by default —
`pvesm set local --content iso,vztmpl,backup,import,snippets`.

- **The admin user/SSH key/sudo grant live in this file, not in
  `initialization.user_account`.** Proxmox's `--cicustom user=...` (which
  `user_data_file_id` sets) *replaces* cloud-init's user-data wholesale —
  it does not merge with `ciuser`/`sshkeys`, so a `user_account` block in
  `k3s_node.tf` would be silently ignored. This matches the pattern the
  operator had already worked out in a prior project
  ([`msavdert/k3s-proxmox`](https://github.com/msavdert/k3s-proxmox),
  `docs/01-vm-provisioning.md`).
- **Why a snippet at all**: the Debian 12 genericcloud image (ADR-0002)
  doesn't ship `qemu-guest-agent`. Without it, Terraform hangs waiting for
  agent readiness on every `apply` that creates or resizes a VM (`agent {
  enabled = true }` in `template.tf`/`k3s_node.tf`).
- If the SSH public key (`var.k3s_ssh_public_key`) is ever rotated, this
  file needs a matching manual update — `qm cloudinit update <vmid>` plus
  a reboot to re-apply it to already-running VMs.
- Two other snippet files (`cka-cloud-init.yaml`, `k3s-cloud-init.yaml`)
  already existed in `/var/lib/vz/snippets/` from earlier, undocumented
  experiments predating this repo's 2026-08-01 clean slate — left in place
  for now, same as the `vnet0` SDN leftover in ADR-0008; revisit as
  cleanup, not blocking.

## Running Terraform

Decrypt the secrets into environment variables for the duration of the
command only — never write them to disk unencrypted or into a plain
`.tfvars` file:

```sh
cd infrastructure/terraform
terraform init

eval "$(sops -d --output-type dotenv secrets.sops.tfvars.json | sed 's/^/export TF_VAR_/')"
terraform plan
terraform apply
unset TF_VAR_proxmox_api_token TF_VAR_proxmox_endpoint
```

`insecure = true` is set by default in `variables.tf` (`proxmox_insecure`)
because the `pve` node currently serves its self-signed PVE cluster CA
certificate, which this machine doesn't trust. Revisit once/if the Proxmox
API gets a certificate from a trusted CA.

## Accessing the k3s node

`k3s-node-01` is at `10.0.1.10` on `k3snet` (ADR-0008), reachable via the
existing `pve` Tailscale subnet router — no per-VM Tailscale needed. The
matching SSH private key is in the **1Password `homelab` vault, item
`homelab-k3s-ssh-key`**, same retrieval pattern as the age key above:

```sh
op item get homelab-k3s-ssh-key --vault homelab --fields private_key --reveal \
  | grep -v '^"$' > ~/.ssh/homelab_k3s
chmod 600 ~/.ssh/homelab_k3s
ssh -i ~/.ssh/homelab_k3s k3sadmin@10.0.1.10
```

If your environment can't route to `10.0.1.0/24` directly (this devbox
couldn't — its Tailscale connectivity only proxies specific peer IPs, not
routes those peers advertise), go through `pve` as a jump host instead:
`ssh -J root@pve -i ~/.ssh/homelab_k3s k3sadmin@10.0.1.10`, or copy the key
onto `pve` and SSH from there. `qm terminal 100` on `pve` gives a serial
console for boot-time debugging when SSH isn't up yet.

## k3s install (already done once, documented here for reference)

Installed directly on the node over the SSH access above — not through
Terraform/cloud-init, so re-running `terraform apply` never touches it:

```sh
ssh -J root@pve -i ~/.ssh/homelab_k3s k3sadmin@10.0.1.10 \
  'curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.36.2+k3s1 \
   INSTALL_K3S_EXEC="server --cluster-init --flannel-backend=none \
   --disable-network-policy --disable=traefik --disable=servicelb \
   --node-ip=10.0.1.10 --tls-san=10.0.1.10 --write-kubeconfig-mode=644" sh -'
```

- **`--cluster-init`**: uses k3s's embedded etcd datastore instead of the
  single-node-only SQLite default, even though this is currently a
  one-node cluster — the operator plans to add server nodes later, and
  etcd is the only k3s datastore that supports joining additional servers.
  Switching datastores after the fact means rebuilding the cluster, so this
  was decided up front.
- **`--flannel-backend=none --disable-network-policy`**: k3s ships Flannel
  as its default CNI; disabled because [ADR-0006](../../docs/decisions/0006-cilium-cni.md)
  already chose Cilium, which will be installed separately (via ArgoCD, see
  [ADR-0007](../../docs/decisions/0007-argocd-gitops.md)). Until Cilium is
  deployed, the node stays `NotReady` and core pods (CoreDNS, etc.) stay
  `Pending` — expected with no CNI, not a fault.
- **`--disable=traefik --disable=servicelb`**: k3s's built-in ingress
  controller and LoadBalancer implementation, disabled for the same
  reason — ingress/LB strategy is a separate, still-open Phase 1 decision
  (see `docs/PLAN.md`), not k3s's defaults.
- **`--write-kubeconfig-mode=644`**: the generated
  `/etc/rancher/k3s/k3s.yaml` is otherwise root-only (`600`), which blocks
  `sudo cat` from a non-root SSH session from reading it cleanly.

Fetch the kubeconfig to a local machine (swap in `10.0.1.10` for the
in-file `127.0.0.1`, and never commit the result — it embeds a client
certificate):

```sh
ssh -J root@pve -i ~/.ssh/homelab_k3s k3sadmin@10.0.1.10 'sudo cat /etc/rancher/k3s/k3s.yaml' \
  | sed 's#127.0.0.1#10.0.1.10#' > ~/.kube/homelab-k3s.yaml
chmod 600 ~/.kube/homelab-k3s.yaml
KUBECONFIG=~/.kube/homelab-k3s.yaml kubectl get nodes
```

This devbox's Tailscale route to `10.0.1.0/24` reaches the k3s API
(`:6443`) directly — no jump host needed for `kubectl`, even though plain
SSH to the node needed one at the time this was written (see above).
