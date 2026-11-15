#!/usr/bin/env python3
"""One-time preparation of the Proxmox host for the lab.

Runs with the ADMINISTRATOR token (op://dotfiles/Proxmox API) and is the only
thing in this repository that does. Run it only when the owner asks.

It makes sure these objects exist and reports each as "exists", "created" or
"updated". It never deletes anything and touches nothing that is not listed:

  - resource pool "homelab", with storage local-zfs as a member
  - SDN VNet "k8s" in zone "localnat", subnet 10.0.6.0/24, SNAT
  - roles HomelabVM and HomelabImageRead
  - user homelab@pve
  - ACLs for that user and, if it exists, its token "tofu"
  - the Talos nocloud image on local:import

Every API call that does not return HTTP 200 stops the script with the
method, path, status and response body. Python 3.11 or newer, standard
library only.

Usage:
  infra/host/prepare.py
  TALOS_VERSION=v1.14.7 infra/host/prepare.py     add the image of another release
"""
import json
import os
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# The host presents a self-signed certificate, so it is not verified. The
# administrator token is sent to this address: PVE_URL exists for tests only.
PVE_URL = os.environ.get("PVE_URL", "https://10.0.0.1:8006")
NODE = os.environ.get("PVE_NODE", "pve")
POOL = "homelab"
ZONE = "localnat"
VNET = "k8s"
SUBNET = "10.0.6.0/24"
GATEWAY = "10.0.6.1"
DHCP_RANGE = "start-address=10.0.6.200,end-address=10.0.6.250"
VM_STORAGE = "local-zfs"
IMAGE_STORAGE = "local"
USER = "homelab@pve"
TOKEN = "tofu"
# The image is used only when a VM is created. The version the nodes run is
# pinned in talos/ and upgraded in place, so this default is changed by hand.
TALOS_VERSION = os.environ.get("TALOS_VERSION", "v1.14.6")
# Image Factory schematic with siderolabs/qemu-guest-agent only.
SCHEMATIC = "ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"
IMAGE = f"talos-{TALOS_VERSION}-nocloud-amd64.qcow2"
IMAGE_URL = f"https://factory.talos.dev/image/{SCHEMATIC}/{TALOS_VERSION}/nocloud-amd64.qcow2"

ROLES = {
    "HomelabVM": {
        "VM.Allocate", "VM.Audit", "VM.Config.CDROM", "VM.Config.CPU",
        "VM.Config.Cloudinit", "VM.Config.Disk", "VM.Config.HWType",
        "VM.Config.Memory", "VM.Config.Network", "VM.Config.Options",
        "VM.PowerMgmt", "VM.GuestAgent.Audit", "Datastore.AllocateSpace",
        "Datastore.Audit", "Pool.Audit",
    },
    "HomelabImageRead": {"Datastore.Audit"},
}
ACLS = [
    (f"/pool/{POOL}", "HomelabVM"),
    (f"/sdn/zones/{ZONE}/{VNET}", "PVESDNUser"),
    (f"/storage/{IMAGE_STORAGE}", "HomelabImageRead"),
]


def die(message):
    print(f"FAILED   {message}", file=sys.stderr)
    sys.exit(1)


def op_read(reference):
    result = subprocess.run(["op", "read", reference], capture_output=True, text=True, check=False)
    value = result.stdout.strip()
    if result.returncode != 0 or not value:
        die(f"cannot read {reference} from 1Password: {result.stderr.strip()}")
    return value


AUTH = None
TLS = ssl.create_default_context()
TLS.check_hostname = False
TLS.verify_mode = ssl.CERT_NONE


def api(method, path, /, **params):
    """Call the Proxmox API and return the "data" member. Stops on any error."""
    body = urllib.parse.urlencode(params).encode() if params else None
    request = urllib.request.Request(
        f"{PVE_URL}/api2/json{path}", data=body, method=method,
        headers={"Authorization": AUTH},
    )
    try:
        with urllib.request.urlopen(request, context=TLS, timeout=120) as response:
            return json.load(response).get("data")
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace").strip()[:400]
        die(f"{method} {path}: HTTP {error.code} {error.reason} {detail}")
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        die(f"{method} {path}: {error}")


def quote(value):
    return urllib.parse.quote(value, safe="")


def wait_task(upid):
    if not isinstance(upid, str) or not upid.startswith("UPID:"):
        die(f"expected a task ID, got {upid!r}")
    for _ in range(300):
        status = api("GET", f"/nodes/{NODE}/tasks/{quote(upid)}/status")
        if status.get("status") == "stopped":
            if status.get("exitstatus") != "OK":
                die(f"task {status.get('type')} ended with {status.get('exitstatus')}")
            return
        time.sleep(2)
    die(f"task {upid} did not finish in 10 minutes")


def report(state, what):
    print(f"{state:<8} {what}", flush=True)


def ensure_pool():
    pools = {pool["poolid"] for pool in api("GET", "/pools")}
    if POOL in pools:
        report("exists", f"pool {POOL}")
    else:
        api("POST", "/pools", poolid=POOL, comment="Kubernetes lab (github.com/msavdert/homelab)")
        report("created", f"pool {POOL}")
    members = api("GET", f"/pools/{POOL}").get("members", [])
    if any(m.get("type") == "storage" and m.get("storage") == VM_STORAGE for m in members):
        report("exists", f"storage {VM_STORAGE} in pool {POOL}")
    else:
        api("PUT", f"/pools/{POOL}", storage=VM_STORAGE)
        report("created", f"storage {VM_STORAGE} in pool {POOL}")


def refuse_foreign_sdn_changes():
    """Applying SDN applies every pending change on the host, not only ours."""
    foreign = []
    for zone in api("GET", "/cluster/sdn/zones?pending=1"):
        if zone.get("state"):
            foreign.append(f"zone {zone.get('zone')} ({zone['state']})")
    for vnet in api("GET", "/cluster/sdn/vnets?pending=1"):
        name = vnet.get("vnet")
        if name == VNET:
            continue
        if vnet.get("state"):
            foreign.append(f"vnet {name} ({vnet['state']})")
        for subnet in api("GET", f"/cluster/sdn/vnets/{name}/subnets?pending=1"):
            if subnet.get("state"):
                foreign.append(f"subnet {subnet.get('subnet')} of {name} ({subnet['state']})")
    if foreign:
        die("the host has pending SDN changes that are not the lab's: "
            + ", ".join(foreign) + "; apply or revert them first")


def pending_field(entry, key):
    """A not yet applied object carries its values under "pending"."""
    return entry.get(key) or (entry.get("pending") or {}).get(key)


def lab_object_state(entry, what):
    """Return "applied" or "new" for one of the lab's own SDN objects."""
    state = entry.get("state")
    if not state:
        return "applied"
    if state != "new":
        die(f"{what} has a pending change of kind {state!r} that this script did not make; "
            "resolve it by hand first")
    return "new"


def ensure_network():
    vnets = {vnet.get("vnet"): vnet for vnet in api("GET", "/cluster/sdn/vnets?pending=1")}
    vnet_state = "missing"
    if VNET in vnets:
        vnet_state = lab_object_state(vnets[VNET], f"vnet {VNET}")
        zone = pending_field(vnets[VNET], "zone")
        if zone != ZONE:
            die(f"vnet {VNET} exists in zone {zone}, expected {ZONE}")
    subnet_state = "missing"
    if vnet_state != "missing":
        subnets = {pending_field(subnet, "cidr"): subnet
                   for subnet in api("GET", f"/cluster/sdn/vnets/{VNET}/subnets?pending=1")}
        if SUBNET in subnets:
            subnet_state = lab_object_state(subnets[SUBNET], f"subnet {SUBNET}")
        elif subnets:
            die(f"vnet {VNET} has other subnets {sorted(str(c) for c in subnets)}; "
                "remove them by hand first")
    if vnet_state == subnet_state == "applied":
        report("exists", f"vnet {VNET}")
        report("exists", f"subnet {SUBNET}")
        return
    # Something has to be created or applied: nothing foreign may ride along.
    refuse_foreign_sdn_changes()
    if vnet_state == "missing":
        api("POST", "/cluster/sdn/vnets", vnet=VNET, zone=ZONE, alias="homelab kubernetes nodes")
        report("created", f"vnet {VNET}")
    else:
        report("exists" if vnet_state == "applied" else "pending", f"vnet {VNET}")
    if subnet_state == "missing":
        api("POST", f"/cluster/sdn/vnets/{VNET}/subnets", subnet=SUBNET, type="subnet",
            gateway=GATEWAY, snat=1, **{"dhcp-range": DHCP_RANGE})
        report("created", f"subnet {SUBNET}")
    else:
        report("exists" if subnet_state == "applied" else "pending", f"subnet {SUBNET}")
    wait_task(api("PUT", "/cluster/sdn"))
    report("applied", "SDN configuration")


def ensure_roles():
    existing = {role["roleid"]: role for role in api("GET", "/access/roles")}
    for name, privileges in ROLES.items():
        wanted = ",".join(sorted(privileges))
        if name not in existing:
            api("POST", "/access/roles", roleid=name, privs=wanted)
            report("created", f"role {name}")
            continue
        current = {p for p in (existing[name].get("privs") or "").split(",") if p}
        if current == privileges:
            report("exists", f"role {name}")
        else:
            api("PUT", f"/access/roles/{name}", privs=wanted)
            report("updated", f"role {name}")


def ensure_user():
    users = {user["userid"] for user in api("GET", "/access/users")}
    if USER in users:
        report("exists", f"user {USER}")
    else:
        api("POST", "/access/users", userid=USER, comment="homelab repository automation")
        report("created", f"user {USER}")


def ensure_acls():
    tokens = {token["tokenid"] for token in api("GET", f"/access/users/{quote(USER)}/token")}
    subjects = [("user", USER)]
    if TOKEN in tokens:
        subjects.append(("token", f"{USER}!{TOKEN}"))
    else:
        report("note", f"token {USER}!{TOKEN} does not exist yet; ACLs set for the user only")
    current = {(entry["path"], entry["type"], entry["ugid"], entry["roleid"])
               for entry in api("GET", "/access/acl")}
    for path, role in ACLS:
        for kind, subject in subjects:
            if (path, kind, subject, role) in current:
                report("exists", f"acl {path} {role} for {subject}")
                continue
            key = "users" if kind == "user" else "tokens"
            api("PUT", "/access/acl", path=path, roles=role, **{key: subject})
            report("created", f"acl {path} {role} for {subject}")


def ensure_image():
    content = api("GET", f"/nodes/{NODE}/storage/{IMAGE_STORAGE}/content?content=import")
    volume = f"{IMAGE_STORAGE}:import/{IMAGE}"
    if any(item.get("volid") == volume for item in content):
        report("exists", f"image {volume}")
    else:
        wait_task(api("POST", f"/nodes/{NODE}/storage/{IMAGE_STORAGE}/download-url",
                      content="import", filename=IMAGE, url=IMAGE_URL))
        report("created", f"image {volume}")


def main():
    global AUTH
    token_id = op_read("op://dotfiles/Proxmox API/username")
    secret = op_read("op://dotfiles/Proxmox API/credential")
    AUTH = f"PVEAPIToken={token_id}={secret}"
    ensure_pool()
    ensure_network()
    ensure_roles()
    ensure_user()
    ensure_acls()
    ensure_image()


if __name__ == "__main__":
    try:
        main()
    except (KeyError, TypeError, AttributeError) as error:
        die(f"unexpected shape of an API response: {type(error).__name__}: {error}")
