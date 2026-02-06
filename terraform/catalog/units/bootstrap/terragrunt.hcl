# Bootstrap unit - generates providers and module calls for all namespaces
# based on the output of the tenants unit
include {
  path =  find_in_parent_folders("root.hcl")
}
terraform {
  source = "${get_repo_root()}//terraform/bootstrap-tenant"
}

dependency "tenants" {
  config_path = values.tenants_path

  mock_outputs = {
    kubeconfigs = {
      "tenant1" = {
        host = "https://127.0.0.1:6443"
        token = "token"
        insecure_skip_tls_verify = true
      }
    }
    namespaces_config = {
      "tenant1" = {
        namespace_name = "tenant1"
        deploy_argo = true
        argo_namespace = "tenant1"
        argo_cluster_labels = {
          type = "tenant"
        }
        cluster_labels = {
          env = "prod"
        }
        tenant_name = "tenant1"
      }
    }
  }
  # mock_outputs_merge_with_state = true
  mock_outputs_allowed_terraform_commands = ["init","validate", "plan"]
}

# Generate root variables required by inputs
generate "variables" {
  path      = "variables.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
variable "argo_password" {
  type        = string
  description = "ArgoCD admin password"
  sensitive   = true
}
EOF
}

# Generate HELM providers for each namespace from tenants output
generate "providers" {
  path      = "genrated_providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
%{ for key, config in dependency.tenants.outputs.kubeconfigs ~}
provider "helm" {
  alias    = "${replace(key, "-", "_")}"
  kubernetes = {
    host     = "${config.host}"
    token    = "${config.token}"
    insecure = ${config.insecure_skip_tls_verify}
  }
}
%{ endfor ~}
EOF
}

# Generate module calls for each namespace from tenants output
generate "modules" {
  path      = "generated_boostrap.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
%{ for key, ns_config in dependency.tenants.outputs.namespaces_config ~}
module "bootstrap_${replace(key, "-", "_")}" {
  source = "${get_repo_root()}//terraform/modules/bootstrap-helm"

  providers = {
    helm = helm.${replace(key, "-", "_")}
  }

  namespace          = "${ns_config.namespace_name}"
  tenant_name        = "${ns_config.tenant_name}"
  deploy_argo        = ${ns_config.deploy_argo}
  argo_namespace     = "${ns_config.argo_namespace}"
  argo_password      = var.argo_password
  
  argo_cluster_labels = ${jsonencode(ns_config.cluster_labels)}
  
}
%{ endfor ~}
EOF
}

inputs = {
  argo_password = values.argo_password
}
