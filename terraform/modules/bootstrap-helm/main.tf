terraform {
  required_providers {
    helm = {
      source = "hashicorp/helm"
    }
  }
}

resource "helm_release" "bootstrap" {
  name       = "bootstrap-tenant"
  chart      = "../../../charts/bootstrap-tenant"
  namespace  = var.namespace
  create_namespace = false # Assumed created by tenants job

  values = [
    yamlencode({
      deployArgo    = var.deploy_argo
      argoNamespace = var.argo_namespace
      tenantName    = var.tenant_name
      
      argoInstance = {
        password = var.deploy_argo ? bcrypt(var.argo_password) : ""
      }
      
      clusterLabels = var.argo_cluster_labels
      
      rootApp = {
        repoURL        = var.root_app_url
        path           = var.root_app_path
        targetRevision = var.root_app_revision
      }
    })
  ]
}
