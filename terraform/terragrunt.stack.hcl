# Terragrunt Explicit Stack Configuration
# Two units: tenants creates namespaces, bootstrap deploys to all namespaces

# Static unit - creates all namespaces, projects, and outputs kubeconfigs
unit "tenants" {
  source = "./units/tenants"
  path   = "tenants"
}

# Single bootstrap unit - generates providers and modules for ALL namespaces
unit "bootstrap" {
  source = "./units/bootstrap"
  path   = "bootstrap"

  values = {
    tenants_path = "../tenants"
  }
}
