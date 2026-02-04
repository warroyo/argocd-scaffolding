# Terragrunt Explicit Stack Configuration
# Generates units for tenant creation and namespace bootstrapping

locals {
  tenants_config = yamldecode(file("tenant/tenants.yaml"))

  # Flatten to map of namespaces for bootstrapping
  namespaces_to_bootstrap = {
    for item in flatten([
      for tenant in local.tenants_config.tenants : [
        for ns in lookup(tenant, "namespaces", []) : {
          key            = "${tenant.name}-${ns.name}"
          tenant_name    = tenant.name
          namespace_name = ns.name
        }
      ]
    ]) : item.key => item
  }
}

# Static unit - creates all namespaces, projects, and outputs kubeconfigs
unit "tenants" {
  source = "./units/tenants"
  path   = "tenants"
}

# Bootstrap units - one per namespace
unit "bootstrap" {
  for_each = local.namespaces_to_bootstrap

  source = "./units/bootstrap"
  path   = "bootstrap/${each.key}"

  values = {
    tenants_path   = "../tenants"
    namespace_key  = each.key
    tenant_name    = each.value.tenant_name
    namespace_name = each.value.namespace_name
  }
}
