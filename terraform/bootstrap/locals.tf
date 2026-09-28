# Per-namespace bootstrap config. Structural values (suffixed namespace names,
# decision-model labels) come from the infra run via var.namespace_config — the
# single infra -> bootstrap contract; secrets are merged in here.

locals {
  # Single source of truth for the repo URL is argocd/repo-config.yaml (also
  # injected into the ApplicationSets by kustomize). TF_VAR_repo_url overrides.
  repo_url = coalesce(var.repo_url, yamldecode(file("${path.module}/../../argocd/repo-config.yaml")).data.repoURL)

  # Every namespace's ManagedEntity, rendered by its ArgoCD host's release — an
  # entity must live in the ArgoCD namespace. See docs/DECISIONS.md #24.
  managed_namespaces = {
    for key, nc in var.namespace_config : key => [
      for m in values(var.namespace_config) : {
        name    = m.namespace
        project = m.tenant_name
        labels = merge(m.cluster_labels, {
          "gitops.platform/namespace"      = m.namespace
          "gitops.platform/argo-namespace" = m.argo_namespace
        })
      } if m.argo_namespace == nc.namespace
    ] if nc.deploy_argo
  }

  bootstrap_config = {
    for key, nc in var.namespace_config : key => {
      namespace          = nc.namespace
      deploy_argo        = nc.deploy_argo
      managed_namespaces = lookup(local.managed_namespaces, key, [])

      repo_url      = local.repo_url
      argo_password = var.argo_password
    }
  }
}
