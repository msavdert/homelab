data "kubernetes_secret_v1" "argocd_initial_admin_secret" {
  depends_on = [helm_release.argocd]
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = kubernetes_namespace_v1.argocd.id
  }
}

output "argocd_url" {
  value       = "http://argocd.local (or http://${var.cilium_load_balancer_ip_range_start})"
  description = "The URL to access the ArgoCD Web UI"
}

output "argocd_username" {
  value       = "admin"
  description = "The default username for ArgoCD"
}

output "argocd_initial_admin_password" {
  value       = data.kubernetes_secret_v1.argocd_initial_admin_secret.data["password"]
  sensitive   = true
  description = "The initial admin password for ArgoCD"
}
