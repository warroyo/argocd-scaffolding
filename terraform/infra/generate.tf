# Renders every config artifact derived from tenants.yaml.
#
# This replaces the old Python generators (generate-bootstrap/tenants/details).
# Because the repo runs Terraform twice (infra -> bootstrap), the infra run can
# render the bootstrap wiring that the second run consumes, plus the ArgoCD
# AppProjects and the post-apply tenant-vars handoff.

locals {
  # Tenant names.
  tenant_names = keys(local.tenant_map)

  # ArgoCD AppProject name per tenant. The infra tenant's project is always named
  # "infra" (the project the ApplicationSets target), regardless of tenant name,
  # so there is no separate hand-authored infra AppProject to keep in sync.
  project_names = {
    for k, v in local.tenant_map : k => lookup(v, "type", "") == "infra" ? "infra" : v.name
  }

  # Per-tenant managing ArgoCD namespace (vcfa-suffixed), taken from any of the
  # tenant's namespace deployments — they all share the same argo_namespace.
  tenant_argo_namespace = {
    for t_name in local.tenant_names : t_name => [
      for k, ns in local.ns_deployments : ns.argo_namespace if ns.tenant_name == t_name
    ][0]
  }

  # Structural wiring keys for the generated bootstrap providers/modules.
  bootstrap_ns = [
    for k, ns in local.ns_deployments : {
      key   = k
      alias = replace(k, "-", "_")
    }
  ]

  # Decision-model invariant: (project, namespace_ref) must be globally unique.
  all_ns_refs = [for k, ns in local.ns_deployments : "${ns.tenant_name}/${ns.ns_name}"]
}

resource "terraform_data" "validate_namespace_refs" {
  lifecycle {
    precondition {
      condition     = length(local.all_ns_refs) == length(distinct(local.all_ns_refs))
      error_message = "Each (project, namespace_ref) must be unique across tenants.yaml — duplicate found."
    }
    precondition {
      condition     = local.infra_count == 1
      error_message = "Exactly one tenant of type 'infra' is required. Found: ${local.infra_count}."
    }
  }
}

# ── ArgoCD AppProjects (one per tenant) + their kustomization ──────────────────

resource "local_file" "appproject" {
  for_each = local.tenant_map
  filename = "${path.module}/../../argocd/projects/${local.project_names[each.key]}.yaml"
  content = templatefile("${path.module}/templates/appproject.yaml.tftpl", {
    name = local.project_names[each.key]
    type = lookup(each.value, "type", "tenant")
  })
}

resource "local_file" "projects_kustomization" {
  filename = "${path.module}/../../argocd/projects/kustomization.yaml"
  content = templatefile("${path.module}/templates/projects-kustomization.yaml.tftpl", {
    projects = sort(values(local.project_names))
  })
}

# ── Post-apply tenant-vars handoff (the single terraform -> argocd contract) ───

resource "local_file" "tenant_vars" {
  for_each = local.tenant_map
  filename = "${path.module}/../../infrastructure/clusters/${each.key}/vars/tenant-vars.yaml"
  content = templatefile("${path.module}/templates/tenant-vars.yaml.tftpl", {
    tenant_uuid    = module.tenant[each.key].project_id
    vpc_name       = "${each.key}-${var.region_name}-vpc"
    argo_namespace = local.tenant_argo_namespace[each.key]
  })
}

resource "local_file" "vars_kustomization" {
  for_each = local.tenant_map
  filename = "${path.module}/../../infrastructure/clusters/${each.key}/vars/kustomization.yaml"
  content  = templatefile("${path.module}/templates/vars-kustomization.yaml.tftpl", {})
}

# ── Bootstrap wiring consumed by the second Terraform run ──────────────────────

resource "local_file" "bootstrap_providers" {
  filename = "${path.module}/../bootstrap/providers.tf"
  content = templatefile("${path.module}/templates/bootstrap-providers.tf.tftpl", {
    namespaces = local.bootstrap_ns
  })
}

resource "local_file" "bootstrap_main" {
  filename = "${path.module}/../bootstrap/main.tf"
  content = templatefile("${path.module}/templates/bootstrap-main.tf.tftpl", {
    namespaces = local.bootstrap_ns
  })
}
