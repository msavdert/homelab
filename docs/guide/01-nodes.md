# 01 Nodes

## What this adds

Three virtual machines, `k8s-1` to `k8s-3` (VM IDs 201 to 203), run Talos
Linux in maintenance mode at 10.0.6.11 to 10.0.6.13. Maintenance mode means
Talos is booted but has no machine configuration yet; it answers
`talosctl --insecure` and waits for one (phase 2). OpenTofu creates the VMs
from `infra/main.tf` and keeps its state encrypted in object storage, so
the VMs can be recreated or changed from any clone with access to vault
`homelab`.

## Before you start

- The host is prepared ([Host](../host.md)): pool `homelab`, VNet `k8s`
  (10.0.6.0/24), the token `homelab@pve!tofu` and the image
  `local:import/talos-v1.14.6-nocloud-amd64.qcow2`.
- [00 Repository](00-repository.md): a clone with `mise install` done.
- The 1Password CLI, and the service account of vault `homelab`. On the
  agent box its token is in `op://dotfiles/homelab-op-service-account/credential`;
  the tasks below read it from there.
- These items in vault `homelab`: `proxmox-tofu` (`username`,
  `credential`), `tofu-state` (`password`), `object-storage`
  (`access-key`, `secret-key`, `endpoint`, `region`).
- Network access to the Proxmox API (`https://10.0.0.1:8006`) and to the
  lab subnet.

## Steps

### 1. Credentials as references

`infra/op.env` lists every value OpenTofu needs, as `op://` references
only:

```
TF_VAR_state_passphrase=op://homelab/tofu-state/password
TF_VAR_proxmox_token_id=op://homelab/proxmox-tofu/username
TF_VAR_proxmox_token_secret=op://homelab/proxmox-tofu/credential
AWS_ACCESS_KEY_ID=op://homelab/object-storage/access-key
AWS_SECRET_ACCESS_KEY=op://homelab/object-storage/secret-key
AWS_REGION=op://homelab/object-storage/region
AWS_ENDPOINT_URL_S3=op://homelab/object-storage/endpoint
```

`op run --env-file infra/op.env -- <command>` resolves them into the
environment of that one command. Nothing is written to disk, and the file
can be committed because it holds no value. `TF_VAR_<name>` sets the
OpenTofu variable `<name>`; the `AWS_*` names are read by the `s3`
backend.

### 2. Backend and state encryption

The `terraform` block in `infra/main.tf` stores state in bucket `homelab`
under `tofu/homelab.tfstate` (D24):

```hcl
backend "s3" {
  bucket                      = "homelab"
  key                         = "tofu/homelab.tfstate"
  use_path_style              = true
  use_lockfile                = true
  skip_credentials_validation = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_s3_checksum            = true
}
```

- The endpoint and region are not in the file; they come from
  `AWS_ENDPOINT_URL_S3` and `AWS_REGION`.
- `use_path_style`: Oracle's S3-compatible endpoint takes the bucket in
  the path, not as a host name.
- The four `skip_*` lines turn off calls to AWS-only services (STS,
  account lookup, the EC2 metadata service) and the region name check.
- `skip_s3_checksum`: the store refuses some of the checksums the AWS
  client sends by default (D24). With this setting, init, plan, apply and
  the lock all worked; the `AWS_REQUEST_CHECKSUM_CALCULATION` variable was
  not needed.
- `use_lockfile`: while a command runs, OpenTofu holds a lock object
  `tofu/homelab.tfstate.tflock` next to the state, written with a
  conditional request that fails if the object already exists. A second
  run is refused instead of overwriting the state (see "Check").

The `encryption` block encrypts the state and saved plans before they
leave the machine:

```hcl
encryption {
  key_provider "pbkdf2" "state" {
    passphrase = var.state_passphrase
  }
  method "aes_gcm" "state" {
    keys = key_provider.pbkdf2.state
  }
  state {
    method   = method.aes_gcm.state
    enforced = true
  }
  plan {
    method   = method.aes_gcm.state
    enforced = true
  }
}
```

`pbkdf2` derives the key from the passphrase in `tofu-state`; `aes_gcm`
encrypts with it. `enforced = true` makes OpenTofu refuse to write
unencrypted state, for example if the block were removed by mistake. If
the passphrase is lost, the state cannot be read; the VMs are then
imported again or recreated.

### 3. The nodes

One resource with `for_each` over a map of the three nodes creates the
VMs with the settings in [Architecture](../architecture.md), "Nodes". The
provider is bpg/proxmox 0.122.0. The lines that matter:

```hcl
locals {
  nodes = {
    k8s-1 = { vm_id = 201, address = "10.0.6.11" }
    k8s-2 = { vm_id = 202, address = "10.0.6.12" }
    k8s-3 = { vm_id = 203, address = "10.0.6.13" }
  }
}

resource "proxmox_virtual_environment_vm" "node" {
  for_each  = local.nodes
  pool_id   = "homelab"
  ...
  disk {
    interface   = "scsi0"
    import_from = "local:import/talos-v1.14.6-nocloud-amd64.qcow2"
    size        = 20
    ...
  }
  disk {
    interface = "scsi1"
    size      = 100
    ...
  }
  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.address}/24"
        gateway = "10.0.6.1"
      }
    }
    dns { servers = ["1.1.1.1", "9.9.9.9"] }
  }
}
```

- `import_from` copies the Talos image into the new system disk through
  the Proxmox API. It needs an uncompressed image of content type
  `import`, which is what the host preparation downloaded. The provider
  needs no SSH access to the host for this.
- `initialization` writes a cloud-init drive (`ide2`). The Talos `nocloud`
  image reads the address from it at boot, so each node comes up at a
  known address (D05).
- `pool_id = "homelab"`: the token can only act inside this pool.
- The VMs have no Proxmox tags; the token is not allowed to set them at
  creation (D28, and "When it goes wrong").

### 4. Tasks

Three mise tasks wrap the commands with `op run`:

| Task | What it does |
|---|---|
| `mise run infra:plan` | `tofu init`, then `tofu plan` |
| `mise run infra:apply` | `tofu init`, then `tofu apply` (asks for `yes`) |
| `mise run infra:pool` | lists the members of pool `homelab` through the API with the `tofu` token |

Each first sets `OP_SERVICE_ACCOUNT_TOKEN` to the service account of vault
`homelab`, because the box's own account cannot read that vault.

### 5. Create the VMs

```sh
mise run infra:plan     # Plan: 3 to add, 0 to change, 0 to destroy.
mise run infra:apply
```

```
proxmox_virtual_environment_vm.node["k8s-1"]: Creation complete after 42s [id=201]
proxmox_virtual_environment_vm.node["k8s-3"]: Creation complete after 43s [id=203]
proxmox_virtual_environment_vm.node["k8s-2"]: Creation complete after 43s [id=202]
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

The provider waits for the QEMU guest agent before it reports a VM as
created. The image carries the agent extension and it already answers in
maintenance mode, so the wait ends as soon as the VM has booted.

## Check

Run on 2026-11-15.

Every node answers in maintenance mode and sees both disks:

```
$ for ip in 10.0.6.11 10.0.6.12 10.0.6.13; do talosctl get disks --insecure --nodes $ip; done
NODE        NAMESPACE   TYPE   ID      VERSION   SIZE     READ ONLY   TRANSPORT
10.0.6.11   runtime     Disk   sda     2         22 GB    false       virtio
10.0.6.11   runtime     Disk   sdb     2         107 GB   false       virtio
(loop0 to loop2 and sr0, the cloud-init drive, trimmed; the same for .12 and .13)
```

`sda` is the 20 GiB system disk; talosctl prints decimal gigabytes, so
21.5 GB shows as 22 GB.

The pool holds exactly the three VMs and the storage:

```
$ mise run infra:pool
qemu	201	k8s-1
qemu	202	k8s-2
qemu	203	k8s-3
storage	local-zfs
```

A fresh clone plans no changes (cloned from the branch of this change,
before the merge):

```
$ git clone ... && mise run infra:plan
proxmox_virtual_environment_vm.node["k8s-1"]: Refreshing state... [id=201]
...
No changes. Your infrastructure matches the configuration.
```

A second run is refused while one holds the lock. One `tofu apply` waited
at its confirmation prompt while a `tofu plan` started:

```
Error: Error acquiring the state lock

Error message: operation error S3: PutObject, https response error
StatusCode: 412, ... api error PreconditionFailed: UnknownError
Lock Info:
  Path:      homelab/tofu/homelab.tfstate
  Operation: OperationTypeApply
```

The stored state is not readable. Downloaded with aws-cli, the object is
JSON with only the keys `encrypted_data`, `encryption_version`, `lineage`,
`meta` and `serial`; it contains no resource, address or VM ID.

## Day-two tasks

- **Change a node** (memory, CPU, disk size): edit `infra/main.tf`, run
  `mise run infra:plan`, read which attributes change and whether the VM
  is replaced, then `mise run infra:apply`. The plan is the authority on
  "in place" or "replace"; no resize has been tried yet.
- **Change the resolvers**: done once (see "When it goes wrong"). The plan
  showed an in-place update; the apply took about 26 seconds per VM, and
  afterwards `talosctl get resolvers --insecure --nodes 10.0.6.11` listed
  1.1.1.1 and 9.9.9.9 with a creation time at the apply, so the provider
  restarted the VMs. Changing the address has not been tried.
- **Recreate a node** (not tried yet): from `infra/`, with the token of
  vault `homelab` exported as in the tasks,
  `op run --env-file op.env -- tofu apply -replace='proxmox_virtual_environment_vm.node["k8s-2"]'`.
  After phase 2 the node also has to be removed from and rejoined to the
  cluster.
- **New Talos image** (not tried yet): download it to `local:import/` (a
  host task, see [Host](../host.md)) and change `import_from`; expect the
  plan to replace the VMs. Once the cluster runs, nodes are upgraded with
  `talosctl upgrade` instead.
- **Provider update**: Renovate proposes it; the lock file
  `infra/.terraform.lock.hcl` changes with it.

## When it goes wrong

- **`403 Permission check failed (/vms/201, VM.Config.Options)` on
  create.** The first apply set the tags `homelab` and `talos`. Creating
  VMs by hand through the API with one option at a time showed that only
  `tags` was refused. The likely reason (inferred, not read in the
  Proxmox source): the right to set tags is checked on `/vms/<id>` before
  the VM is a pool member, so the pool's rights do not apply yet.
  Setting tags on the VM after creation worked. The tags were dropped
  (D28). Proxmox removed the half-created VMs and their disks by itself.
- **The nodes had only one resolver.** The first version set only
  1.1.1.1; [Architecture](../architecture.md) says 1.1.1.1 and 9.9.9.9.
  Found in the audit and fixed with an in-place apply.
- **A failed `op read` or `curl` did not fail the task.** mise runs a
  task with `sh -o errexit`, without `pipefail`, so in `infra:pool` a
  failing `curl` was hidden by `jq`, which exits 0 on empty input. The
  tasks now run in bash with `set -euo pipefail` (`shell = "bash -c"`).
- **`could not read secret ...: error initializing client`.** One `op
  read` failed once with this message and succeeded when repeated a minute
  later. If it persists, check that `OP_SERVICE_ACCOUNT_TOKEN` is set.

## Sources

- bpg/proxmox documentation:
  [provider](https://github.com/bpg/terraform-provider-proxmox/blob/main/docs/index.md)
  (token authentication, `import_from` uses the API and needs no SSH) and
  [`proxmox_virtual_environment_vm`](https://github.com/bpg/terraform-provider-proxmox/blob/main/docs/resources/virtual_environment_vm.md)
  (argument names, `memory.floating = 0` disables ballooning,
  `import_from` needs an uncompressed `import` image).
- [rgl/terraform-proxmox-talos](https://github.com/rgl/terraform-proxmox-talos),
  `proxmox.tf`: the resource shape for Talos VMs (OVMF, q35, static
  cloud-init address). It uses SSH and `file_id`; this repository uses
  `import_from` instead.
- OpenTofu documentation:
  [state encryption](https://opentofu.org/docs/language/state/encryption/)
  (`pbkdf2`, `aes_gcm`, `enforced`, variables allowed in the block) and the
  [s3 backend](https://opentofu.org/docs/language/settings/backends/s3/)
  (the `skip_*` options, `use_path_style`, `use_lockfile`, the
  `AWS_ENDPOINT_URL_S3` and `AWS_REGION` variables).
- The host test of 2026-11-15 ([Handoff](../handoff.md) at phase 0): the
  VM parameters that worked through the raw API.
