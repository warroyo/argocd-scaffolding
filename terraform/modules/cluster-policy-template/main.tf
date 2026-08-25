# the policy template. this is an org scoped resource that wraps an OPA
# Gatekeeper ConstraintTemplate containing the Rego enforcement logic. only org
# admins can create templates. creating a template auto generates a
# ClusterPolicySchema of type custom-policy named "<template_name>:custom-policy".
resource "kubernetes_manifest" "policy_template" {
  # The platform writes .spec.input before Terraform's first server-side apply,
  # leaving a "before-first-apply" field manager that conflicts on every update.
  # Terraform is the declared owner here. Local divergence from the vendored
  # upstream — keep it when re-vendoring. See docs/DECISIONS.md #23.
  field_manager {
    force_conflicts = true
  }

  manifest = {
    "apiVersion" = "policy.management.kubernetes.vmware.com/v1alpha1"
    "kind"       = "ClusterPolicyTemplate"
    "metadata" = {
      "name"      = var.template_name
      "namespace" = "@org"
      # Platform-stamped; declared so a forced apply doesn't drop it. Same
      # reason as the cluster-policy module. See docs/DECISIONS.md #23.
      "labels" = {
        "mgmt.k8s.vmware.com/policy-type" = "custom-policy"
      }
    }
    "spec" = {
      "templateType" = "OPAGatekeeper"
      "objectKind"   = "ConstraintTemplate"
      # the embedded Gatekeeper ConstraintTemplate. its metadata.name must match
      # the ClusterPolicyTemplate metadata.name above.
      "object" = {
        "apiVersion" = "templates.gatekeeper.sh/v1"
        "kind"       = "ConstraintTemplate"
        "metadata" = {
          "name" = var.template_name
        }
        "spec" = {
          "crd" = {
            "spec" = {
              "names" = {
                "kind" = var.constraint_kind
              }
              "validation" = {
                "openAPIV3Schema" = {
                  "type"       = "object"
                  "properties" = var.parameters_schema
                }
              }
            }
          }
          "targets" = [
            {
              "target" = var.target
              "rego"   = "package ${var.template_name}\n\n${var.rego_rules}"
            }
          ]
        }
      }
    }
  }
}
