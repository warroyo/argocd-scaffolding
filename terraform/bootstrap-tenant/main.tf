# Bootstrap Tenant Module
# Configures a tenant namespace in ArgoCD and optionally deploys ArgoCD

# Deploy ArgoCD instance if deploy_argo is true
module "argocd-instance" {
  count  = var.deploy_argo ? 1 : 0
  source = "../modules/argocd-instance"

  name         = "argocd"
  namespace    = var.namespace
  password     = var.argo_password
  argo_version = var.argo_version
}

# Always deploy ArgoNamespace CRD to register this namespace with ArgoCD
resource "kubernetes_manifest" "argo_namespace" {
  manifest = {
    apiVersion = "field.vmware.com/v1"
    kind       = "ArgoNamespace"
    metadata = {
      name      = var.namespace
      namespace = var.namespace
    }
    spec = {
      argoNamespace  = var.argo_namespace
      clusterLabels  = var.argo_cluster_labels
      project        = var.tenant_name
      serviceAccount = ""
    }
  }
}

# Outputs
output "argo_deployed" {
  value = var.deploy_argo
}

output "argo_ip" {
  value = var.deploy_argo ? module.argocd-instance[0].server_ip : null
}

