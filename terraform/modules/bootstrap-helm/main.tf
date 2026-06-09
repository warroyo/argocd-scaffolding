terraform {
  required_providers {
    helm = {
      source = "hashicorp/helm"
    }
  }
}

resource "helm_release" "bootstrap" {
  name             = "bootstrap-tenant"
  chart            = "../../charts/bootstrap-tenant"
  namespace        = var.config.namespace
  create_namespace = false # Assumed created by tenants job

  values = [
    yamlencode({
      deployArgo    = var.config.deploy_argo
      argoNamespace = var.config.argo_namespace
      tenantName    = var.config.tenant_name

      argoInstance = {
        password = var.config.deploy_argo ? bcrypt(var.config.argo_password) : ""
      }

      clusterLabels = var.config.cluster_labels

      rootApp = {
        repoURL = var.config.repo_url
      }

      akoSecret = {
        enabled                  = var.config.ako.enabled
        username                 = var.config.ako.username
        password                 = var.config.ako.password
        certificateAuthorityData = var.config.ako.ca_data
      }
    })
  ]
}
