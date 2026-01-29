locals {
  raw_remote_data = yamldecode(data.http.root_app.response_body)
  modified_remote_object = merge(local.raw_remote_data, {
    metadata = merge(local.raw_remote_data.metadata, {
      namespace = var.supervisor_namespace
    })
    spec = merge(local.raw_remote_data.spec, {
      destination = {
          name = var.supervisor_namespace
          namespace = var.supervisor_namespace
        }
    })
  })
}

module "argocd-instance" {
  source = "../modules/argocd-instance"
  name = "argocd-1"
  namespace = var.supervisor_namespace
  password = var.argo_password
  argo_version = "3.0.19+vmware.1-vks.1"
  providers = {
    kubernetes = kubernetes
  }
}

module "ns-attach" {
  source = "../modules/argocd-ns-attach"
  ns_name = var.supervisor_namespace
  argo_namespace = var.supervisor_namespace
  argo_cluster_labels = {
    type = "infra"
  }
  argo_project = "default"
}

data "http" "root_app" {
  url = var.root_app

  retry {
    attempts = 3
    min_delay_ms = 1000
  }
}

resource "kubernetes_manifest" "root_app" {
  manifest = local.modified_remote_object
}



output "argo_ip" {
  value = module.argocd-instance.server_ip
}

output "argo_password" {
  value = module.argocd-instance.admin_password
  sensitive = true
}