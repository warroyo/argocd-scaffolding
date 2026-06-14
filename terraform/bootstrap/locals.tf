# Per-namespace bootstrap config. The structural part (suffixed namespace names,
# decision-model labels) comes from the infra run via var.namespace_config — the
# single terraform -> bootstrap contract — so this stack never re-parses
# tenants.yaml or guesses vcfa-suffixed names. Secrets are merged in here.
#
# The generated main.tf only wires providers to modules and references
# local.bootstrap_config[<key>]; no values are baked into the generated HCL, so
# it only changes when the SET of namespaces changes.

locals {
  bootstrap_config = {
    for key, nc in var.namespace_config : key => {
      namespace      = nc.namespace
      tenant_name    = nc.tenant_name
      deploy_argo    = nc.deploy_argo
      argo_namespace = nc.argo_namespace
      cluster_labels = nc.cluster_labels

      repo_url      = var.repo_url
      argo_password = var.argo_password
      ako = {
        enabled  = var.ako_secret_enabled
        username = var.ako_username
        password = var.ako_password
        ca_data  = var.ako_ca_data
      }
    }
  }
}
