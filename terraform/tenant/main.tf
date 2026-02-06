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

        cluster_labels = try(
            [for ns in local.tenant_map[t_name].namespaces : lookup(ns, "argo_labels", {}) if ns.name == ns_key][0],
            {}
        )
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


data "vcfa_kubeconfig" "ns_kubeconfig" {
  for_each = local.ns_deployments

  project_name              = each.value.tenant_name
  supervisor_namespace_name = each.value.ns_name
}

output "kubeconfigs" {
  description = "Map of namespace name to kubeconfig details"
  value = {
    for key, config in data.vcfa_kubeconfig.ns_kubeconfig : key => {
      host                      = config.host
      token                     = config.token
      insecure_skip_tls_verify  = config.insecure_skip_tls_verify
    }
  }
  sensitive = true
}

output "namespaces_config" {
  description = "Map of namespace name to bootstrap configuration"
  value = {
    for key, ns in local.ns_deployments : key => {
      tenant_name    = ns.tenant_name
      namespace_name = ns.ns_name
      deploy_argo    = ns.deploy_argo
      argo_namespace = ns.argo_namespace
      project_id     = ns.project_id
      cluster_labels = ns.cluster_labels
    }
  }
}