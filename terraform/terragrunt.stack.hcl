# Terragrunt Explicit Stack Configuration
# Generates units for tenant creation and namespace bootstrapping

locals {
  tenants_config = yamldecode(file("tenant/tenants.yaml"))

  # Flatten to list of namespaces that need bootstrapping (deploy_argo = true)
  namespaces_to_bootstrap = flatten([
    for tenant in local.tenants_config.tenants : [
      for ns in lookup(tenant, "namespaces", []) : {
        key            = "${tenant.name}-${ns.name}"
        tenant_name    = tenant.name
        namespace_name = ns.name
        deploy_argo    = lookup(ns, "deploy_argo", false)
      } if lookup(ns, "deploy_argo", false) == true
    ]
  ])
}

# Static unit - creates all namespaces, projects, and outputs kubeconfigs
unit "tenants" {
  source = "./units/tenants"
  path   = "tenants"
}

# Dynamic units - one per namespace that needs ArgoCD bootstrapping
dynamic "unit" {
  for_each = { for ns in local.namespaces_to_bootstrap : ns.key => ns }

  labels = ["bootstrap_${unit.key}"]

  content {
    source = "./units/bootstrap"
    path   = "bootstrap/${unit.key}"

    values = {
      tenants_path   = "../tenants"
      namespace_key  = unit.key
      tenant_name    = unit.value.tenant_name
      namespace_name = unit.value.namespace_name
    }
  }
}
