resource "kubernetes_secret_v1" "argocd_app_of_apps_git_repo" {
  count      = var.install_argocd_app_of_apps_git_repo_secret ? 1 : 0
  depends_on = [kubernetes_namespace_v1.argocd]
  metadata {
    namespace = kubernetes_namespace_v1.argocd.id
    name      = "argocd-app-of-apps-git-repo"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }
  data = {
    type     = "git"
    url      = var.argocd_app_of_apps_git_repo_secret_url
    username = var.argocd_app_of_apps_git_repo_secret_username
    password = var.argocd_app_of_apps_git_repo_secret_password_or_token
  }
}

# --- Admin User for External Access ---

resource "kubernetes_service_account_v1" "admin_user" {
  metadata {
    name      = "admin-user"
    namespace = "kube-system"
  }
}

resource "kubernetes_cluster_role_binding_v1" "admin_user_binding" {
  metadata {
    name = "admin-user-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.admin_user.metadata[0].name
    namespace = kubernetes_service_account_v1.admin_user.metadata[0].namespace
  }
}

resource "kubernetes_secret_v1" "admin_user_token" {
  metadata {
    name      = "admin-user-token"
    namespace = "kube-system"
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.admin_user.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"
}
