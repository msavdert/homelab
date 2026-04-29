data "helm_template" "cilium" {
  name         = "cilium"
  namespace    = "kube-system"
  repository   = "https://helm.cilium.io"
  chart        = "cilium"
  version      = "1.19.3"
  kube_version = var.kubernetes_version
  set {
    name  = "ipam.mode"
    value = "kubernetes"
  }
  set {
    name  = "kubeProxyReplacement"
    value = "true"
  }
  set {
    name  = "securityContext.capabilities.ciliumAgent"
    value = "{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}"
  }
  set {
    name  = "securityContext.capabilities.cleanCiliumState"
    value = "{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}"
  }
  set {
    name  = "cgroup.autoMount.enabled"
    value = "false"
  }
  set {
    name  = "cgroup.hostRoot"
    value = "/sys/fs/cgroup"
  }
  set {
    name  = "k8sServiceHost"
    value = "localhost"
  }
  set {
    name  = "k8sServicePort"
    value = "7445"
  }
  # L2 Loadbalancer
  # See: https://docs.cilium.io/en/stable/network/l2-announcements/
  set {
    name  = "l2announcements.enabled"
    value = "true"
  }
  set {
    name  = "k8sClientRateLimit.qps"
    value = "50"
  }
  set {
    name  = "k8sClientRateLimit.burst"
    value = "100"
  }
  # Ingress Controller
  # See: https://docs.cilium.io/en/stable/network/servicemesh/ingress/
  set {
    name  = "ingressController.enabled"
    value = "true"
  }
  set {
    name  = "ingressController.loadbalancerMode"
    value = "dedicated"
  }
  # Gateway API
  # See: https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/
  set {
    name  = "gatewayAPI.enabled"
    value = "true"
  }
  set {
    name  = "gatewayAPI.enableAlpn"
    value = "true"
  }
  set {
    name  = "gatewayAPI.enableAppProtocol"
    value = "true"
  }
  set {
    name  = "gatewayAPI.gatewayClass.create"
    value = "true"
    type  = "string"
  }
  # Egress Gateway
  # See: https://docs.cilium.io/en/stable/network/egress-gateway/egress-gateway/
  set {
    name  = "egressGateway.enabled"
    value = "true"
  }
  set {
    name  = "bpf.masquerade"
    value = "true"
  }
}