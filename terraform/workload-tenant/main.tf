
locals {
  region_name = var.region_name
  vpc_name = var.vpc_name
  zone_name = var.zone_name
  tenants = yamldecode(file("tenants.yml"))
  tenants_map = { for tenant in local.tenants : tenant.name => tenant }
}

module "supervisor_namespace" {
  for_each = local.tenants_map
  source = "git::https://github.com/warroyo/vcfa-terraform-examples.git//modules/namespace?ref=main"
  zone_name = local.zone_name
  region_name = local.region_name
  vpc_name = local.vpc_name
  name = each.key
}

data "vcfa_kubeconfig" "kubeconfig" {
  for_each = local.tenants_map
  project_name              = "default-project"
  supervisor_namespace_name = module.supervisor_namespace[each.key].namespace
  depends_on = [ module.supervisor_namespace ]
}


module "argocd-instance" {
  for_each = local.tenants_map
  source = "git::https://github.com/warroyo/vcfa-terraform-examples.git//modules/argocd-instance?ref=main"
  name = "argocd"
  namespace = module.supervisor_namespace[each.key].namespace
  providers = {
    kubernetes = kubernetes.tenant-1
  }
}