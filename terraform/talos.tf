# =============================================================================
# Talos Image Factory
# =============================================================================

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = [
          "siderolabs/iscsi-tools",
          "siderolabs/util-linux-tools",
          "siderolabs/qemu-guest-agent",
        ]
      }
    }
  })
}

# A single data source is sufficient since both node types use the same schematic.
data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "nocloud"
}

# =============================================================================
# Cilium — pre-rendered manifest injected into Talos machine config
# =============================================================================

data "helm_template" "cilium" {
  provider     = helm.local
  name         = "cilium"
  namespace    = "kube-system"
  repository   = "https://helm.cilium.io"
  chart        = "cilium"
  version      = var.cilium_version
  kube_version = var.kubernetes_version

  # Minimum settings required for Cilium to work on Talos.
  # See: https://docs.cilium.io/en/stable/installation/talos/
  set = [
    { name = "ipam.mode", value = "kubernetes" },
    { name = "kubeProxyReplacement", value = "true" },
    { name = "securityContext.capabilities.ciliumAgent", value = "{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" },
    { name = "securityContext.capabilities.cleanCiliumState", value = "{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" },
    { name = "cgroup.autoMount.enabled", value = "false" },
    { name = "cgroup.hostRoot", value = "/sys/fs/cgroup" },
    { name = "k8sServiceHost", value = "localhost" },
    { name = "k8sServicePort", value = "7445" },
    { name = "ingressController.enabled", value = "true" },
    { name = "ingressController.loadbalancerMode", value = "shared" },
    { name = "gatewayAPI.enabled", value = "false" },
  ]
}

# =============================================================================
# Talos Machine Secrets & Configuration
# =============================================================================

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = "https://${var.cluster_vip_shared_ip}:6443"
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = "https://${var.cluster_vip_shared_ip}:6443"
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = concat([var.cluster_vip_shared_ip], [for ip, _ in var.node_data.controlplanes : ip])
}

# =============================================================================
# Talos Machine Configuration Apply
# =============================================================================

resource "talos_machine_configuration_apply" "controlplane" {
  depends_on                  = [proxmox_virtual_environment_vm.kubernetes_control_plane]
  for_each                    = var.node_data.controlplanes
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = each.key

  config_patches = [
    templatefile("${path.module}/templates/machine_config_patches_controlplane.tftpl", {
      hostname        = each.value.hostname != null ? each.value.hostname : format("%s-cp-%s", var.cluster_name, index(keys(var.node_data.controlplanes), each.key))
      install_disk    = each.value.install_disk
      install_image   = data.talos_image_factory_urls.this.urls.installer
      dns             = var.domain_name_server
      ip_address      = "${each.key}/24"
      network         = var.network
      network_gateway = var.network_gateway
      vip_shared_ip   = var.cluster_vip_shared_ip
      cilium_manifest = data.helm_template.cilium.manifest
    }),
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  depends_on                  = [proxmox_virtual_environment_vm.kubernetes_worker]
  for_each                    = var.node_data.workers
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = each.key

  config_patches = [
    templatefile("${path.module}/templates/machine_config_patches_worker.tftpl", {
      hostname             = each.value.hostname != null ? each.value.hostname : format("%s-worker-%s", var.cluster_name, index(keys(var.node_data.workers), each.key))
      install_disk         = each.value.install_disk
      install_image        = data.talos_image_factory_urls.this.urls.installer
      dns                  = var.domain_name_server
      ip_address           = "${each.key}/24"
      network              = var.network
      network_gateway      = var.network_gateway
      longhorn_disk_device = var.longhorn_disk_device
    }),
  ]
}

# =============================================================================
# Cluster Bootstrap & Kubeconfig
# =============================================================================

resource "talos_machine_bootstrap" "this" {
  depends_on           = [talos_machine_configuration_apply.controlplane]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = [for ip, _ in var.node_data.controlplanes : ip][0]
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on           = [talos_machine_bootstrap.this]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = [for ip, _ in var.node_data.controlplanes : ip][0]
  endpoint             = var.cluster_vip_shared_ip
}

resource "local_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename = "${path.module}/kubeconfig"
}

resource "local_file" "talosconfig" {
  content  = data.talos_client_configuration.this.talos_config
  filename = "${path.module}/talosconfig"
}
