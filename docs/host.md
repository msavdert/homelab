# Host

What exists on the Proxmox host for the lab, how it was created and how to
check it. Everything here was created on 2026-11-15 through the Proxmox API
and is reproduced by `infra/host/prepare.py`.

The script needs the administrator token and is the only thing in the
repository that uses it. It only adds or updates the lab's own objects and
never deletes. The version in the repository was run against the prepared
host on 2026-11-15: it reported every object as existing and made no
change. Its create, update and failure paths were run against an in-memory
stand-in for the API, not against the host; the objects on the host were
created by the same API calls made by hand. How Proxmox reports an object
that was created but not yet applied (a `state` of `new`, values under
`pending`) was seen once for a VNet and is assumed for a subnet.

Applying an SDN change on Proxmox applies every pending SDN change on the
host. Whenever the script has to create or apply the lab's network, it
first stops if a zone, a VNet or a subnet that is not the lab's has a
pending change. If an earlier
run was interrupted after creating the VNet but before applying, the next
run sees the lab's own pending objects and applies them.

## Objects that belong to the lab

| Object | Value |
|---|---|
| Resource pool | `homelab`, with storage `local-zfs` as a member |
| SDN VNet | `k8s` in zone `localnat`, subnet 10.0.6.0/24, gateway 10.0.6.1, SNAT on |
| Role `HomelabVM` | see below |
| Role `HomelabImageRead` | `Datastore.Audit` |
| User | `homelab@pve` (no password login is needed; it only owns the token) |
| Image | `local:import/talos-v1.14.6-nocloud-amd64.qcow2` |
| VM IDs | 201 to 203 are reserved for the nodes |

Nothing else on the host belongs to the lab.

## Access rights

Role `HomelabVM`:

```
VM.Allocate VM.Audit VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit
VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network
VM.Config.Options VM.PowerMgmt VM.GuestAgent.Audit
Datastore.AllocateSpace Datastore.Audit Pool.Audit
```

| Path | Role | Why |
|---|---|---|
| `/pool/homelab` | `HomelabVM` | manage guests in the pool; the pool's storage member inherits it, which allows disks on `local-zfs` |
| `/sdn/zones/localnat/k8s` | `PVESDNUser` | attach a NIC to the bridge |
| `/storage/local` | `HomelabImageRead` | read the Talos image to import it |

The rights are granted to the user and to its token. A token with privilege
separation has only the rights granted to both.

What the test on 2026-11-15 showed with a token holding exactly these
rights: it sees no guest outside the pool; it created a VM with an imported
disk, resized the disk, started it, queried the guest agent, stopped and
destroyed it; reading the config of VM 120, stopping VM 124 and creating a
VM outside the pool were refused with 403. Not tested: whether
`Datastore.AllocateSpace` on `local-zfs` allows anything on volumes of other
guests. Deleting a volume normally needs `Datastore.Allocate`, which the
role does not have.

## The token

The token `homelab@pve!tofu` exists (privilege separation on). Its ID and
secret are in 1Password, vault `homelab`, item `proxmox-tofu`, fields
`username` and `credential`. `infra/host/prepare.py` granted it the three
roles above on 2026-11-15.

If it has to be recreated: Proxmox UI, Datacenter, Permissions, API Tokens,
Add; user `homelab@pve`, token ID `tofu`, privilege separation on. Store
the new secret in the same item, then run `infra/host/prepare.py` again.

Check, from the box. The box reads vault `homelab` with that vault's own
service account, hence the helper function:

```
hl() { OP_SERVICE_ACCOUNT_TOKEN="$(op read op://dotfiles/homelab-op-service-account/credential)" op "$@"; }
printf 'header = "Authorization: PVEAPIToken=%s=%s"\n' \
  "$(hl read op://homelab/proxmox-tofu/username)" "$(hl read op://homelab/proxmox-tofu/credential)" |
  curl -sk -K - https://10.0.0.1:8006/api2/json/access/permissions
```

The secret is passed on standard input so that it does not appear in the
process list.

The answer must list exactly four paths: `/pool/homelab`,
`/storage/local-zfs`, `/storage/local` and `/sdn/zones/localnat/k8s`. Any
other path means the token is too wide. Checked on 2026-11-15: exactly
these four.

## Adding a Talos image for a new version

Nodes are upgraded in place with `talosctl upgrade`; the image on the host
is used only when a VM is created. To make new VMs start on a newer
release:

```
TALOS_VERSION=v1.14.7 infra/host/prepare.py
```

## State of the host worth knowing

Observed through the API on 2026-11-15; not managed by this repository.

- The ZFS pool is two disks striped. One disk failure loses every guest.
- There are no scheduled backup jobs on the host.
- No swap, no memory ballooning on any guest. About 48 GiB RAM was free
  before the lab nodes were created; the nodes take 24 GiB.
- CPU is the tight resource: 12 threads, load average around 10.
