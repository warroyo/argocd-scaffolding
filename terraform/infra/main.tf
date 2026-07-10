locals {
  tenant_config = yamldecode(file("${path.module}/tenants.yaml"))

  tenant_map = {
    for t in local.tenant_config.tenants : "${t.name}" => t
  }

  infra_tenants = {
    for k, v in local.tenant_map : k => v if lookup(v, "type", "") == "infra"
  }

  infra_count       = length(local.infra_tenants)
  infra_tenant_name = local.infra_count == 1 ? keys(local.infra_tenants)[0] : null

  ns_deployments = merge([
    for t_name, t_mod in module.tenant : {
      for ns_key, ns_val in t_mod.namespaces :
      "${t_name}-${ns_key}" => {
        tenant_name = t_name
        # ns_key is the logical namespace name from tenants.yaml (e.g. "dev-1").
        # ns_name is the vcfa-suffixed name actually created (e.g. "dev-1-abcde").
        ns_ref      = ns_key
        ns_name     = ns_val.name
        project_id  = t_mod.project_id
        deploy_argo = ns_val.deploy_argo

        # Suffixed name of the namespace running the managing ArgoCD instance.
        # null (instead of an opaque index crash) when the tenant's argo_namespace
        # doesn't resolve to a deploy_argo namespace on the infra tenant — a
        # precondition in generate.tf turns that into a readable error.
        argo_namespace = try([
          for infra_ns_key, infra_ns_val in module.tenant[local.infra_tenant_name].namespaces : infra_ns_val.name
          if infra_ns_val.deploy_argo == true && infra_ns_key == lookup(local.tenant_map[t_name], "argo_namespace", "argocd")
        ][0], null)

        # Decision-model labels, computed once here (the chart adds the suffixed
        # gitops.platform/namespace label at install time from .Release.Namespace).
        cluster_labels = merge(
          try([for ns in local.tenant_map[t_name].namespaces : lookup(ns, "argo_labels", {}) if ns.name == ns_key][0], {}),
          {
            "type"                          = "supervisor-ns"
            "gitops.platform/project"       = t_name
            "gitops.platform/namespace-ref" = ns_key
            "gitops.platform/environment"   = try([for ns in local.tenant_map[t_name].namespaces : lookup(ns, "environment", "dev") if ns.name == ns_key][0], "dev")
          }
        )
      }
    }
  ]...)
}


module "tenant" {
  for_each                      = local.tenant_map
  source                        = "../modules/tenant"
  region_name                   = var.region_name
  avi_enabled                   = var.avi_enabled
  project_name                  = each.value.name
  vpc_connectivity_profile_name = lookup(each.value, "vpc_connectivity_profile_name", null)
  vpc_private_cidr              = lookup(each.value, "vpc_private_cidr", null)
  providers = {
    kubernetes = kubernetes.vcfa-org
  }
  # Defaults for the optional per-namespace settings live in ONE place: the
  # tenant module's typed optional() object (modules/tenant/variables.tf).
  # Unset keys are passed through as null so the module default applies.
  namespaces = {
    for ns in lookup(each.value, "namespaces", []) : ns.name => {
      name           = ns.name
      zone_name      = lookup(ns, "zone_name", null)
      deploy_argo    = lookup(ns, "deploy_argo", null)
      storage_limit  = lookup(ns, "storage_limit", null)
      class_name     = lookup(ns, "class_name", null)
      mem_limit      = lookup(ns, "mem_limit", null)
      cpu_limit      = lookup(ns, "cpu_limit", null)
      storage_policy = lookup(ns, "storage_policy", null)
    }
  }
}

# Per-namespace bootstrap config consumed by the second Terraform run. This is
# the single terraform -> bootstrap contract: it carries the vcfa-SUFFIXED
# namespace names (not knowable until infra applies) and the decision-model
# labels, so the bootstrap stack never has to re-parse tenants.yaml or guess the
# suffixed names. The Makefile passes it as TF_VAR_namespace_config; secrets
# (repo_url, passwords, AKO) are merged in on the bootstrap side.
output "namespace_config" {
  description = "Per-namespace bootstrap config keyed by '<tenant>-<namespace_ref>'."
  value = {
    for key, ns in local.ns_deployments : key => {
      namespace      = ns.ns_name
      tenant_name    = ns.tenant_name
      deploy_argo    = ns.deploy_argo
      argo_namespace = ns.argo_namespace
      cluster_labels = ns.cluster_labels
    }
  }
}
