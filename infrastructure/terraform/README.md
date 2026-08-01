# infrastructure/terraform

Terraform against the Proxmox API (`bpg/proxmox` provider), implementing
Phase 0 of [`docs/PLAN.md`](../../docs/PLAN.md): a code-provisioned Debian
12 cloud-init VM template. Design decisions: [ADR-0002](../../docs/decisions/0002-cloud-init-vm-template.md)
(image/template strategy) and [ADR-0003](../../docs/decisions/0003-sops-age-secrets.md)
(SOPS + age secrets).

Workload VMs (Terraform clones of the template) are **not** built here yet
— this module only creates the template itself.

**Note:** the base cloud image is staged onto Proxmox storage with a manual
`wget` run as root, not downloaded by Terraform — the Proxmox API's
URL-download endpoints reject API-token auth even with correct permissions.
See the comment at the top of `image.tf` and the ADR-0002 addendum for the
full explanation and the exact command.

## What's here

| File            | Purpose                                                         |
| --------------- | ---------------------------------------------------------------- |
| `versions.tf`   | Provider/Terraform version pins                                  |
| `providers.tf`  | Proxmox provider configuration                                   |
| `variables.tf`  | Inputs, with defaults matching the live `pve` host                |
| `image.tf`      | References the Debian 12 cloud qcow2 staged on Proxmox storage `local` (see note below) |
| `template.tf`   | Builds the cloud-init VM template on storage `local-zfs`          |
| `outputs.tf`    | Exposes the template VM ID/name for later modules to clone from   |
| `secrets.sops.tfvars.json` | SOPS-encrypted Proxmox API token + endpoint (committed, encrypted) |

## One-time local bootstrap

Install the tools this module needs:

```sh
brew tap hashicorp/tap
brew install hashicorp/tap/terraform age sops
```

Generate a local age keypair if you don't already have one (the private key
never leaves this machine, never goes in git):

```sh
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

The repo's [`.sops.yaml`](../../.sops.yaml) at the repo root already
references the age public key used to encrypt `secrets.sops.tfvars.json`.
If you're setting this up on a **new** machine (not the one that originally
encrypted the file), you need the *matching private key* — there is no way
to decrypt without it; ask the operator to transfer `keys.txt` out of band
(e.g. via a password manager), it is deliberately never committed.

## Proxmox API token bootstrap (already done once, documented here for reference)

Terraform authenticates as a dedicated, least-privilege Proxmox user, not
`root@pam`. This was provisioned once, directly on the host over
`ssh root@pve`:

```sh
pveum role add TerraformProv -privs \
  'VM.Allocate,VM.Clone,VM.Config.CDROM,VM.Config.Cloudinit,VM.Config.CPU,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.Audit,VM.PowerMgmt,Datastore.AllocateSpace,Datastore.Audit,Datastore.AllocateTemplate,SDN.Use'

pveum user add terraform@pve --comment 'Terraform provisioning (bpg/proxmox provider) - homelab repo'
pveum acl modify / -user terraform@pve -role TerraformProv
pveum user token add terraform@pve provider --privsep 0 \
  --comment 'infrastructure/terraform bpg/proxmox provider token'
```

- **User**: `terraform@pve` (PVE realm, not PAM — no login shell, API-only).
- **Role**: `TerraformProv`, a custom role scoped to VM lifecycle and
  datastore access needed to download images and clone/build VMs. Explicitly
  excludes `Sys.Modify`, `Realm.Allocate`, `Permissions.Modify`, and any
  other cluster/host-admin privileges — this token cannot touch anything
  outside VM/CT lifecycle and the two datastores in use.
- **Token**: `terraform@pve!provider`, `--privsep 0` (token inherits the
  user's own ACLs rather than needing separate permissions granted to the
  token itself — simpler for a single-purpose automation user). The token
  secret is shown exactly once at creation time; it was captured
  immediately and encrypted (see below), never stored in shell history or
  plaintext on disk.

If this ever needs to be redone (token rotated, host rebuilt), regenerate
the token with `pveum user token add terraform@pve provider --privsep 0` and
re-encrypt as described next.

### Encrypting the token

```sh
cat > /tmp/secrets_plain.json <<'EOF'
{
  "proxmox_api_token": "terraform@pve!provider=<token-secret>",
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
# review the plan, then, once ready:
# terraform apply
unset TF_VAR_proxmox_api_token TF_VAR_proxmox_endpoint
```

`insecure = true` is set by default in `variables.tf` (`proxmox_insecure`)
because the `pve` node currently serves its self-signed PVE cluster CA
certificate, which this machine doesn't trust. Revisit once/if the Proxmox
API gets a certificate from a trusted CA.

Do not run `terraform apply` without explicit operator confirmation —
creating the template touches the live host.
