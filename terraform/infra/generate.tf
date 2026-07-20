# Renders every config artifact derived from tenants.yaml (AppProjects, tenant-vars
# handoff, bootstrap wiring the second run consumes). See docs/DECISIONS.md #1.

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

  # Decision-model invariant: (project, namespace_ref) must be unique. The yaml
  # decode already rejects duplicate namespace names within one tenant, but the
  # ns_deployments merge() would silently collapse a cross-tenant key collision
  # (keys are "<tenant>-<ref>", so tenant "a-b"/ref "c" collides with "a"/"b-c").
  total_namespaces = sum([for t in values(local.tenant_map) : length(lookup(t, "namespaces", []))])
}

resource "terraform_data" "validate_namespace_refs" {
  lifecycle {
    precondition {
      condition     = length(local.ns_deployments) == local.total_namespaces
      error_message = "Namespace deployment keys collided — a '<tenant>-<namespace_ref>' key is not unique across tenants.yaml."
    }
    precondition {
      condition     = local.infra_count == 1
      error_message = "Exactly one tenant of type 'infra' is required. Found: ${local.infra_count}."
    }
    precondition {
      condition     = alltrue([for ns in values(local.ns_deployments) : ns.argo_namespace != null])
      error_message = "Every tenant's argo_namespace must name a namespace on the infra tenant that has deploy_argo: true. Check argo_namespace in tenants.yaml."
    }
    precondition {
      condition     = length(local.unknown_policy_names) == 0
      error_message = "Unknown policy in tenants.yaml: ${join(", ", local.unknown_policy_names)}. Valid policies: ${join(", ", keys(local.policy_catalog))}."
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
    # Optional per-tenant allow-list of git repos (tenants.yaml `source_repos`).
    # Defaults open because tenant repos are not known at render time.
    source_repos = lookup(each.value, "source_repos", ["*"])
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
