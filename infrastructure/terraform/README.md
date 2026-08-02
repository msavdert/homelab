# infrastructure/terraform

Terraform against the Proxmox API (`bpg/proxmox` provider), implementing
Phase 0 of [`docs/PLAN.md`](../../docs/PLAN.md): a code-provisioned Debian
12 cloud-init VM template, fully automated end to end. Design decisions:
[ADR-0002](../../docs/decisions/0002-cloud-init-vm-template.md)
(image/template strategy), [ADR-0003](../../docs/decisions/0003-sops-age-secrets.md)
(SOPS + age secrets), [ADR-0004](../../docs/decisions/0004-root-pam-terraform-token.md)
(why Terraform authenticates as `root@pam`), and
[ADR-0008](../../docs/decisions/0008-k3snet-private-sdn-network.md) (the
private, NAT-isolated `k3snet` SDN network cluster VMs attach to).

Workload VMs (Terraform clones of the template) are **not** built here yet
— this module only creates the template itself.

## What's here

| File            | Purpose                                                         |
| --------------- | ---------------------------------------------------------------- |
| `versions.tf`   | Provider/Terraform version pins                                  |
| `providers.tf`  | Proxmox provider configuration                                   |
| `variables.tf`  | Inputs, with defaults matching the live `pve` host                |
| `image.tf`      | Downloads the Debian 12 cloud qcow2 into Proxmox storage `local`  |
| `template.tf`   | Builds the cloud-init VM template on storage `local-zfs`          |
| `network.tf`    | The `localnat` SDN zone + `k3snet` VNet/subnet cluster VMs attach to (ADR-0008) |
| `outputs.tf`    | Exposes the template VM ID/name for later modules to clone from   |
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
