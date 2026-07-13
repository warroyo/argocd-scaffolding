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
  atomic           = true  # auto-rollback/uninstall on failed install so a retry doesn't hit "name still in use"
  cleanup_on_fail  = true

  values = [
    yamlencode({
      deployArgo    = var.config.deploy_argo
      argoNamespace = var.config.argo_namespace
      tenantName    = var.config.tenant_name

      # argo_password must already be a bcrypt hash (see variables.tf). It is NOT
      # hashed here: bcrypt() is non-deterministic and would rewrite the secret on
      # every apply, and the chart's secret template stores the value as-is.
      argoInstance = {
        password = var.config.deploy_argo ? var.config.argo_password : ""
      }

      clusterLabels = var.config.cluster_labels

      rootApp = {
        repoURL = var.config.repo_url
      }
    })
  ]
}
