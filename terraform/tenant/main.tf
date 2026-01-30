locals {
  tenant_config = yamldecode(file("${path.module}/tenants.yaml"))
  
  tenant_map = { 
    for t in local.tenant_config.tenants : "${t.name}" => t 
  }

  infra_tenants = {
    for k, v in local.tenant_map : k => v if lookup(v, "type", "") == "infra"
  }

  all_project_ids = [
    for mod in module.tenant : mod.project_id
  ]

  infra_count = length(local.infra_tenants)
  validate_single_infra = local.infra_count != 1 ? file("ERROR: Exactly one tenant of type 'infra' is required. Found: ${local.infra_count}") : true

  infra_tenant_name = local.infra_count == 1 ? keys(local.infra_tenants)[0] : null

  ns_deployments = merge([
    for t_name, t_mod in module.tenant : {
      for ns_key, ns_val in t_mod.namespaces :
      "${t_name}-${ns_key}" => {
        tenant_name    = t_name
        ns_name        = ns_val.name
        project_id     = t_mod.project_id
        deploy_argo    = ns_val.deploy_argo
        
        argo_namespace = local.infra_tenant_name != null ? [
          for infra_ns_key, infra_ns_val in module.tenant[local.infra_tenant_name].namespaces : infra_ns_val.name 
          if infra_ns_val.deploy_argo == true && infra_ns_key == local.tenant_map[t_name].argo_namespace
        ][0] : "argocd" 
      }
    }
  ]...)
}


module "tenant" {
  for_each = local.tenant_map
  source = "../modules/tenant"
  region_name = var.region_name
  project_name = each.value.name
  providers = {
    kubernetes = kubernetes.vcfa-org
  }
  argo_namespace = lookup(each.value, "argo_namespace", "argocd")
  namespaces = {
    for ns in lookup(each.value, "namespaces", []) : ns.name => {
      name          = ns.name
      zone_name     = lookup(ns, "zone_name", "zone1")
      deploy_argo   = lookup(ns, "deploy_argo", false)
      storage_limit = lookup(ns, "storage_limit", "102400Mi")
      class_name    = lookup(ns, "class_name", "small")
      mem_limit     = lookup(ns, "mem_limit", "10000Mi")
      cpu_limit     = lookup(ns, "cpu_limit", "10000M")
      storage_policy = lookup(ns, "storage_policy", "vSAN Default Storage Policy")
    }
  }
}

module "namepace_boostrap_catalog" {
  source = "../modules/namespace-bp-catalog"
  enabled_projects = local.all_project_ids
  api_token = var.vcfa_refresh_token
  project_id = module.tenant[local.infra_tenant_name].project_id
  vcfa_url = var.vcfa_url
  org = var.vcfa_org
  for_each = local.infra_tenants
}

//boostrap each NS 



resource "vra_deployment" "deploy_ns_bootstrap" {
  for_each = local.ns_deployments

  name        = "${each.key}-deployment"
  description = "Deployment for namespace ${each.value.ns_name} in tenant ${each.value.tenant_name}"


  catalog_item_id      = module.namepace_boostrap_catalog[local.infra_tenant_name].catalog_id
  catalog_item_version = module.namepace_boostrap_catalog[local.infra_tenant_name].bp_version
  project_id           = each.value.project_id

  inputs = {
    namespace    = each.value.ns_name
    argo_namespace = each.value.argo_namespace
    # cluster_labels  = {type = "tenant" }
    argo_project   = each.value.tenant_name
  }
}

output "response" {
  value = module.namepace_boostrap_catalog[local.infra_tenant_name].catalog_api_response
}