
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
  class_name = each.value["namespace_class"]
}

data "vcfa_kubeconfig" "ops-kubeconfig" {
  project_name              = "default-project"
  supervisor_namespace_name = var.ops_namespace
}


data "vcfa_kubeconfig" "kubeconfig" {
  for_each = local.tenants_map
  project_name              = "default-project"
  supervisor_namespace_name = module.supervisor_namespace[each.key].namespace
  depends_on = [ module.supervisor_namespace ]
}


resource "kubernetes_role" "argo-cd-limited-role" {
  for_each = local.tenants_map

  metadata {
    name = "tenant-limited-role"
    namespace =  module.supervisor_namespace[each.key].namespace
  }

  rule {
    api_groups     = ["argoproj.io"]
    resources      = ["applications","appprojects","applicationsets"]
    verbs          = ["get", "list", "watch","create","update","delete","sync","patch"]
  }
  provider = local.tenant_k8s_providers["tenant-1"]
}


module "argocd-instance" {
  for_each = local.tenants_map
  source = "git::https://github.com/warroyo/vcfa-terraform-examples.git//modules/argocd-instance?ref=main"
  name = "argocd"
  namespace = module.supervisor_namespace[each.key].namespace
  providers = {
    kubernetes.tenant = local.tenant_k8s_providers["tenant-1"]
  }
  # give limited role for the tenant namespace 
  role_name = kubernetes_role.argo-cd-limited-role[each.key].metadata[0].name
  role_type = "Role"
}

module "ops-registration" {
  for_each = local.tenants_map
  source = "git::https://github.com/warroyo/vcfa-terraform-examples.git//modules/argocd-attach-sv-namespace?ref=main"
  sa_name = "${each.key}-tenant-argo-sa"
  argocd_namespace = var.ops_namespace
  namespace = module.supervisor_namespace[each.key].namespace
  providers = {
    ops-k8s = kubernetes.ops
    tenant-k8s =local.tenant_k8s_providers[each.key]
  }

}