locals {
  tenant_config = yamldecode(file("${path.module}/tenants.yaml"))
  
  tenant_map = { 
    for t in local.tenant_config.tenants : "${t.name}" => t 
  }
}

module "tenant" {
  for_each = local.tenant_map
  source = "../modules/tenant"
  region_name = var.region_name
  project_name = each.value.name
  providers = {
    kubernetes = kubernetes.vcfa-org
  }
  namespaces = {
    for ns in lookup(each.value, "namespaces", []) : ns.name => {
      name          = ns.name
      zone_name     = lookup(ns, "zone_name", "zone1")
      storage_limit = lookup(ns, "storage_limit", "102400Mi")
      class_name    = lookup(ns, "class_name", "small")
      mem_limit     = lookup(ns, "mem_limit", "10000Mi")
      cpu_limit     = lookup(ns, "cpu_limit", "10000M")
      storage_policy = lookup(ns, "storage_policy", "vSAN Default Storage Policy")
    }
  }
}





