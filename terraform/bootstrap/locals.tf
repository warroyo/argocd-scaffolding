# Per-namespace bootstrap config. The structural part (suffixed namespace names,
# decision-model labels) comes from the infra run via var.namespace_config — the
# single terraform -> bootstrap contract — so this stack never re-parses
# tenants.yaml or guesses vcfa-suffixed names. Secrets are merged in here.
#
# The generated main.tf only wires providers to modules and references
# local.bootstrap_config[<key>]; no values are baked into the generated HCL, so
# it only changes when the SET of namespaces changes.

locals {
  # Single source of truth for the repo URL is argocd/repo-config.yaml (also
  # injected into the ApplicationSets by kustomize). TF_VAR_repo_url overrides.
  repo_url = coalesce(var.repo_url, yamldecode(file("${path.module}/../../argocd/repo-config.yaml")).data.repoURL)

  bootstrap_config = {
    for key, nc in var.namespace_config : key => {
      namespace      = nc.namespace
      tenant_name    = nc.tenant_name
      deploy_argo    = nc.deploy_argo
      argo_namespace = nc.argo_namespace
      cluster_labels = nc.cluster_labels

      repo_url      = local.repo_url
      argo_password = var.argo_password
    }
  }
}
