locals {
  raw_remote_data = yamldecode(data.http.root_app.response_body)
  modified_remote_object = merge(local.raw_remote_data, {
    metadata = merge(local.raw_remote_data.metadata, {
      namespace = var.supervisor_namespace
    })
    spec = merge(local.raw_remote_data.spec, {
      destination = {
          name = "supervisor-ns-${var.supervisor_namespace}"
          namespace = var.supervisor_namespace
        }
    })
  })
}

module "argocd-instance" {
  count = var.deploy_argo ? 1 : 0 
  source = "../argocd-instance"
  name = "argocd-1"
  namespace = var.supervisor_namespace
  password = var.argo_password
  argo_version = "3.0.19+vmware.1-vks.1"
}

module "ns-attach" {
  source = "../argocd-ns-attach"
  ns_name = var.supervisor_namespace
  argo_namespace = var.argo_ns
  argo_cluster_labels = var.argo_cluster_labels
  argo_project = var.argo_project
}

data "http" "root_app" {
  count = var.deploy_argo ? 1 : 0 
  url = var.root_app

  retry {
    attempts = 3
    min_delay_ms = 1000
  }
}

resource "kubernetes_manifest" "root_app" {
  count = var.deploy_argo ? 1 : 0 
  manifest = local.modified_remote_object
}



# output "argo_ip" {
#   value = module.argocd-instance.server_ip
# }

# output "argo_password" {
#   value = module.argocd-instance.admin_password
#   sensitive = true
# }