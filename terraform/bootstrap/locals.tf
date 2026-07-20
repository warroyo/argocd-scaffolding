# Per-namespace bootstrap config. Structural values (suffixed namespace names,
# decision-model labels) come from the infra run via var.namespace_config — the
# single infra -> bootstrap contract; secrets are merged in here.

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
