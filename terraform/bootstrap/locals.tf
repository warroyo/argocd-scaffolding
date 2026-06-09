# Per-namespace bootstrap config, computed live from the single source of truth
# (terraform/infra/tenants.yaml). The generated main.tf only wires providers to
# modules and references local.bootstrap_config[<key>] — no values are baked into
# the generated HCL, so it only changes when the SET of namespaces changes.
#
# The decision-model cluster labels are computed here, in one place.

locals {
  tenants = yamldecode(file("${path.module}/../infra/tenants.yaml")).tenants

  bootstrap_config = merge([
    for t in local.tenants : {
      for ns in lookup(t, "namespaces", []) : "${t.name}-${ns.name}" => {
        namespace      = ns.name
        tenant_name    = t.name
        deploy_argo    = lookup(ns, "deploy_argo", false)
        argo_namespace = lookup(t, "argo_namespace", "argocd")

        cluster_labels = merge(lookup(ns, "argo_labels", {}), {
          "type"                          = "supervisor-ns"
          "gitops.platform/project"       = t.name
          "gitops.platform/namespace-ref" = ns.name
          "gitops.platform/environment"   = lookup(ns, "environment", "dev")
        })

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
  ]...)
}
