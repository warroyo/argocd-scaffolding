locals {
   argo_ns_manifest_object = {
    apiVersion = "field.vmware.com/v1"
    kind       = "ArgoNamespace"
    metadata = {
      name = var.ns_name
      namespace = var.ns_name
    }
    spec = {
      argoNamespace  = var.argo_namespace
      clusterLabels  = var.argo_cluster_labels
      project        = var.argo_project
      serviceAccount = ""
    }
  }
}


resource "kubernetes_manifest" "ns-attach" {
  manifest = local.argo_ns_manifest_object
}