
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
}

module "supervisor_namespace" {
  source = "git::https://github.com/warroyo/vcfa-terraform-examples.git//modules/namespace?ref=main"
  zone_name = local.zone_name
  region_name = local.region_name
  vpc_name = local.vpc_name
  name = "argocd-ops"
}

module "argocd-instance" {
  source = "git::https://github.com/warroyo/vcfa-terraform-examples.git//modules/argocd-instance?ref=main"
  name = "argocd-ops"
  namespace = module.supervisor_namespace.namespace
  providers = {
    kubernetes = kubernetes.vcfa-ns
  }
}



resource "kubernetes_manifest" "root-app" {
  depends_on = [ module.argocd-instance ]
  manifest = local.modified_app
  provider = kubernetes.vcfa-ns
}