#!/usr/bin/env bash
# Machine configuration and node operations. Called by the talos:* mise
# tasks from the repository root; see docs/guide/02-cluster.md.
#
# The cluster secrets live in 1Password item `talos` (vault homelab), field
# `secrets`, as the whole `talosctl gen secrets` file. They are written only
# to a private tmpfs directory that is removed on exit.
set -euo pipefail

CLUSTER=homelab
ENDPOINT=https://10.0.6.10:6443
NODES=(k8s-1 k8s-2 k8s-3)
SECRETS_REF=op://homelab/talos/secrets
: "${KUBERNETES_VERSION:?set in mise.toml}"
: "${TALOSCONFIG:?set in mise.toml}"
: "${KUBECONFIG:?set in mise.toml}"

die() { printf '%s\n' "$*" >&2; exit 1; }

# k8s-N has the address 10.0.6.1N.
address() {
  case "$1" in
    k8s-1 | k8s-2 | k8s-3) printf '10.0.6.1%s' "${1#k8s-}" ;;
    *) die "unknown node: $1 (expected one of ${NODES[*]})" ;;
  esac
}

# The service account of vault homelab, for this process only.
use_homelab_vault() {
  local token
  token="$(op read op://dotfiles/homelab-op-service-account/credential)"
  export OP_SERVICE_ACCOUNT_TOKEN="$token"
}

tmp=""
cleanup() { if [ -n "$tmp" ]; then rm -rf "${tmp:?}"; fi; }
trap cleanup EXIT
make_tmp() {
  [ -z "$tmp" ] || return 0
  tmp="$(mktemp -d -p "${XDG_RUNTIME_DIR:-/dev/shm}" talos.XXXXXX)"
}

fetch_secrets() {
  use_homelab_vault
  op read "$SECRETS_REF" >"$tmp/secrets.yaml"
}

# Generate the secrets once and store them. Refuses if the item exists.
cmd_secrets() {
  use_homelab_vault
  # A failed listing stops the script (pipefail); only a listing without
  # the title counts as absent.
  local count
  count="$(op item list --vault homelab --format json | jq '[.[] | select(.title == "talos")] | length')"
  [ "$count" -eq 0 ] || die "item talos already exists in vault homelab (${count:-?}); not overwriting"
  make_tmp
  talosctl gen secrets -o "$tmp/secrets.yaml"
  jq -Rs '{title: "talos", category: "SECURE_NOTE",
           fields: [{id: "secrets", label: "secrets", type: "CONCEALED", value: .}]}' \
    "$tmp/secrets.yaml" | op item create --vault homelab - >/dev/null
  op read "$SECRETS_REF" | cmp - "$tmp/secrets.yaml"
  echo "stored item talos in vault homelab; the read-back matches"
}

# Print the full machine config of one node to stdout.
cmd_render() {
  local node="${1:?node}"
  address "$node" >/dev/null
  make_tmp
  fetch_secrets
  talosctl gen config "$CLUSTER" "$ENDPOINT" \
    --with-secrets "$tmp/secrets.yaml" \
    --kubernetes-version "$KUBERNETES_VERSION" \
    --output-types controlplane --output "$tmp/base.yaml" \
    --with-docs=false --with-examples=false \
    --config-patch @talos/patches/cluster.yaml \
    --config-patch-control-plane @talos/patches/controlplane.yaml >/dev/null
  talosctl machineconfig patch "$tmp/base.yaml" \
    --patch "@talos/nodes/$node.yaml" --output "$tmp/$node.yaml"
  cat "$tmp/$node.yaml"
}

# Apply the config to one node. Extra arguments go to talosctl apply-config,
# for example --insecure (maintenance mode) or --dry-run.
cmd_apply() {
  local node="${1:?node}"
  shift
  local ip
  ip="$(address "$node")"
  make_tmp
  cmd_render "$node" >"$tmp/apply.yaml"
  talosctl --nodes "$ip" apply-config --file "$tmp/apply.yaml" "$@"
}

# Write the admin talosconfig, derived from the stored secrets.
cmd_config() {
  make_tmp
  fetch_secrets
  talosctl gen config "$CLUSTER" "$ENDPOINT" \
    --with-secrets "$tmp/secrets.yaml" \
    --output-types talosconfig --output "$tmp/talosconfig" >/dev/null
  install -m 600 "$tmp/talosconfig" "$TALOSCONFIG"
  talosctl config endpoint 10.0.6.11 10.0.6.12 10.0.6.13
  talosctl config node 10.0.6.11
  echo "wrote $TALOSCONFIG"
}

cmd_bootstrap() {
  talosctl --nodes 10.0.6.11 bootstrap
}

# From k8s-1, or from the node given (when k8s-1 is down).
cmd_kubeconfig() {
  local ip
  ip="$(address "${1:-k8s-1}")"
  talosctl --nodes "$ip" kubeconfig "$KUBECONFIG" --force --merge=false
  chmod 600 "$KUBECONFIG"
  echo "wrote $KUBECONFIG"
}

# Upgrade one node to the installer image in patches/cluster.yaml.
cmd_upgrade() {
  local node="${1:?node}"
  shift
  local ip image
  ip="$(address "$node")"
  image="$(awk '$1 == "image:" && $2 ~ /^factory\.talos\.dev\// {print $2}' talos/patches/cluster.yaml)"
  [ -n "$image" ] || die "no installer image in talos/patches/cluster.yaml"
  talosctl --nodes "$ip" upgrade --image "$image" "$@"
}

# Upgrade Kubernetes to KUBERNETES_VERSION (mise.toml) through k8s-1; extra
# arguments go to talosctl (--dry-run shows the plan).
cmd_upgrade_k8s() {
  talosctl --nodes "$(address k8s-1)" upgrade-k8s --to "$KUBERNETES_VERSION" "$@"
}

# Print the Image Factory ID of schematic.yaml.
cmd_schematic() {
  curl -fsS -X POST --data-binary @talos/schematic.yaml https://factory.talos.dev/schematics | jq -r .id
}

cmd="${1:-}"
[ -n "$cmd" ] || die "usage: talos.sh secrets|render|apply|config|bootstrap|kubeconfig|upgrade|upgrade-k8s|schematic [args]"
shift
case "$cmd" in
  secrets) cmd_secrets "$@" ;;
  render) cmd_render "$@" ;;
  apply) cmd_apply "$@" ;;
  config) cmd_config "$@" ;;
  bootstrap) cmd_bootstrap "$@" ;;
  kubeconfig) cmd_kubeconfig "$@" ;;
  upgrade) cmd_upgrade "$@" ;;
  upgrade-k8s) cmd_upgrade_k8s "$@" ;;
  schematic) cmd_schematic "$@" ;;
  *) die "unknown command: $cmd" ;;
esac
