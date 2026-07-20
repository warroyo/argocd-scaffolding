# Custom VKS cluster policy catalog. Design + how to extend: CLAUDE.md
# "Adding a policy" and docs/ARCHITECTURE.md "Cluster policy + namespace
# self-service".

locals {
  policy_catalog = {
    "require-namespace-labels" = {
      template_name   = "requirenamespacelabels"
      constraint_kind = "RequireNamespaceLabels"
      rego            = file("${path.module}/rego/require-namespace-labels.rego")
      parameters_schema = {
        project = { type = "string" }
        allowedEnvironments = {
          type  = "array"
          items = { type = "string" }
        }
        syncServiceAccounts = {
          type  = "array"
          items = { type = "string" }
        }
      }
      target_resources = [
        { apiGroups = [""], kinds = ["Namespace"] },
      ]
      # Namespace is cluster-scoped — a namespace selector doesn't apply.
      selector_mode = "none"
    }

    "gitops-namespace-containment" = {
      template_name   = "gitopsnamespacecontainment"
      constraint_kind = "GitopsNamespaceContainment"
      rego            = file("${path.module}/rego/gitops-namespace-containment.rego")
      parameters_schema = {
        project = { type = "string" }
        syncServiceAccounts = {
          type  = "array"
          items = { type = "string" }
        }
      }
      target_resources = [
        { apiGroups = [""], kinds = ["Service", "ConfigMap", "Secret", "ServiceAccount", "PersistentVolumeClaim"] },
        { apiGroups = ["apps"], kinds = ["Deployment", "StatefulSet", "DaemonSet"] },
        { apiGroups = ["batch"], kinds = ["Job", "CronJob"] },
        { apiGroups = ["networking.k8s.io"], kinds = ["Ingress"] },
        { apiGroups = ["gateway.networking.k8s.io"], kinds = ["HTTPRoute", "Gateway"] },
        { apiGroups = ["networking.istio.io"], kinds = ["Gateway"] },
        { apiGroups = ["rbac.authorization.k8s.io"], kinds = ["Role", "RoleBinding"] },
      ]
      # NotIn also matches unlabeled namespaces — no platform exclusion list.
      selector_mode = "not_in"
    }

    "hostname-ownership" = {
      template_name   = "hostnameownership"
      constraint_kind = "HostnameOwnership"
      rego            = file("${path.module}/rego/hostname-ownership.rego")
      parameters_schema = {
        allowedSuffixes = {
          type  = "array"
          items = { type = "string" }
        }
      }
      target_resources = [
        { apiGroups = ["networking.k8s.io"], kinds = ["Ingress"] },
        { apiGroups = ["gateway.networking.k8s.io"], kinds = ["HTTPRoute", "Gateway"] },
        { apiGroups = ["networking.istio.io"], kinds = ["Gateway"] },
      ]
      selector_mode = "in"
    }

    "service-exposure" = {
      template_name   = "serviceexposure"
      constraint_kind = "ServiceExposure"
      rego            = file("${path.module}/rego/service-exposure.rego")
      parameters_schema = {
        denyNodePort = { type = "boolean" }
      }
      target_resources = [
        { apiGroups = [""], kinds = ["Service"] },
      ]
      selector_mode = "in"
    }
  }

  # Raw (tenant, policy) selections from tenants.yaml, deliberately kept free of
  # any policy_catalog lookup — an unknown policy name here must not crash
  # locals evaluation, only fail the readable precondition in generate.tf.
  tenant_policy_selections = merge([
    for t_name, t in local.tenant_map : {
      for p_name, p in lookup(t, "policies", {}) : "${t_name}-${p_name}" => {
        tenant_name = t_name
        policy_name = p_name
        parameters  = lookup(p, "parameters", {})
        enforcement = lookup(p, "enforcement", "dryrun")
      }
    }
  ]...)

  unknown_policy_names = toset([
    for v in values(local.tenant_policy_selections) : v.policy_name
    if !contains(keys(local.policy_catalog), v.policy_name)
  ])

  # Resolved instances — the `if` filter runs before the value expression, so
  # the policy_catalog index below never evaluates for an unknown policy name.
  # project / syncServiceAccounts are computed identity values and always win
  # the merge (last), regardless of what a tenants.yaml `parameters:` block
  # supplies — they are not tenant-overridable.
  tenant_policies = {
    for k, v in local.tenant_policy_selections : k => merge(v, {
      catalog = local.policy_catalog[v.policy_name]
      parameters = merge(
        { allowedEnvironments = ["dev", "test", "prod"] },
        v.parameters,
        {
          project             = v.tenant_name
          syncServiceAccounts = ["system:serviceaccount:platform-gitops:tenant-sync-${v.tenant_name}"]
        }
      )
    })
    if contains(keys(local.policy_catalog), v.policy_name)
  }

  enabled_templates = {
    for p_name in toset([for v in values(local.tenant_policies) : v.policy_name]) :
    p_name => local.policy_catalog[p_name]
  }
}

module "policy_template" {
  for_each = local.enabled_templates
  source   = "../modules/cluster-policy-template"

  template_name     = each.value.template_name
  constraint_kind   = each.value.constraint_kind
  parameters_schema = each.value.parameters_schema
  rego_rules        = each.value.rego

  providers = {
    kubernetes = kubernetes.vcfa-org
  }
}

# The ClusterPolicySchema (<template>:custom-policy) generates asynchronously
# after the ClusterPolicyTemplate — a policy applied immediately can fail with
# "schema not available". A short wait avoids depending on a manual re-apply.
resource "time_sleep" "policy_schema_ready" {
  depends_on      = [module.policy_template]
  create_duration = "15s"
}

module "policy" {
  for_each = local.tenant_policies
  source   = "../modules/cluster-policy"

  policy_scope       = "project"
  project_name       = each.value.tenant_name
  policy_name        = each.value.policy_name
  policy_schema_name = "${each.value.catalog.template_name}:custom-policy"

  cluster_namespace_selector = (
    each.value.catalog.selector_mode == "not_in" ? {
      matchExpressions = [{
        key      = "gitops.platform/project"
        operator = "NotIn"
        values   = [each.value.tenant_name]
      }]
      } : each.value.catalog.selector_mode == "in" ? {
      matchExpressions = [{
        key      = "gitops.platform/project"
        operator = "In"
        values   = [each.value.tenant_name]
      }]
    } : null
  )

  policy_input = {
    parameters                = each.value.parameters
    targetKubernetesResources = each.value.catalog.target_resources
    enforcementAction         = each.value.enforcement
  }

  providers = {
    kubernetes = kubernetes.vcfa-org
  }

  # Project namespace(s) must exist before a project-scoped policy can land in
  # them; the schema must exist before the policy can reference it.
  depends_on = [module.tenant, time_sleep.policy_schema_ready]
}
