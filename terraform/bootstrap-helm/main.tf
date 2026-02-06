terraform {
  required_providers {
    helm = {
      source = "hashicorp/helm"
    }
  }
}

resource "helm_release" "bootstrap" {
  name       = "bootstrap-tenant"
  chart      = "../../charts/bootstrap-tenant"
  namespace  = var.namespace
  create_namespace = false # Assumed created by tenants job

  # Pass values to Helm chart
  set [
  {
    name  = "deployArgo"
    value = var.deploy_argo
  }

  {
    name  = "argoNamespace"
    value = var.argo_namespace
  }

 {
    name  = "tenantName"
    value = var.tenant_name
  }

   {
    name  = "argoInstance.password"
    value = var.deploy_argo ? bcrypt(var.argo_password) : ""
  }

  dynamic "set" {
    for_each = var.argo_cluster_labels
    content {
      name  = "clusterLabels.${set.key}"
      value = set.value
    }
  }

  # Root App Configuration
  set {
    name  = "rootApp.repoURL"
    value = var.root_app_url
  }
    
  set {
    name  = "rootApp.path"
    value = var.root_app_path
  }
    
  set {
    name  = "rootApp.targetRevision"
    value = var.root_app_revision
  }
}
