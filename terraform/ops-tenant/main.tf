
locals {
  region_name = var.region_name
  vpc_name = var.vpc_name
  zone_name = var.zone_name
  root_yaml = file("${path.module}/../../argocd/root/root.yml")
  app_object = yamldecode(local.root_yaml)
  modified_app = merge(
    local.app_object,
    {
      metadata = merge( local.app_object.metadata,{
        namespace = module.supervisor_namespace.namespace
      })
      spec = merge(local.app_object.spec,{
        destination = {
          name = module.supervisor_namespace.namespace
          namespace = module.supervisor_namespace.namespace 
        } 
      })
    }
  )
  sup_ns_connection = {
    kubeconfig = data.vcfa_kubeconfig.kubeconfig.kube_config_raw
  }

}

module "supervisor_namespace" {
  source = "git::https://github.com/warroyo/vcfa-terraform-examples.git//modules/namespace?ref=main"
  zone_name = local.zone_name
  region_name = local.region_name
  vpc_name = local.vpc_name
  name = "argocd-ops"
}

data "vcfa_kubeconfig" "kubeconfig" {
  project_name              = "default-project"
  supervisor_namespace_name = module.supervisor_namespace.namespace
  depends_on = [ module.supervisor_namespace ]
}


module "argocd-instance" {
  source = "../modules/argocd-instance"
  name = "argocd-ops"
  namespace = module.supervisor_namespace.namespace
  cluster = local.sup_ns_connection
  password = var.argo_password
}


resource "k8sconnect_object" "app" {
  yaml_body          = yamlencode(local.modified_app)
  cluster = local.sup_ns_connection
  depends_on = [data.vcfa_kubeconfig.kubeconfig]
}