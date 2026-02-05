# Bootstrap unit - generates providers and module calls for all namespaces
# based on the output of the tenants unit
include {
  path =  find_in_parent_folders("root.hcl")
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
        argo_password = "password"
        argo_cluster_labels = {
          type = "tenant"
        }
        argo_project = "tenant1"
      }
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

terraform {
  source = "${get_repo_root()}//terraform/bootstrap-tenant"
}

# Generate providers for each namespace from tenants output
generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
%{ for key, config in dependency.tenants.outputs.kubeconfigs ~}
provider "kubernetes" {
  alias    = "${replace(key, "-", "_")}"
  host     = "${config.host}"
  token    = "${config.token}"
  insecure = ${config.insecure_skip_tls_verify}
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
  source = "../modules/bootstrap-tenant"

  providers = {
    kubernetes = kubernetes.${replace(key, "-", "_")}
  }

  namespace          = "${ns_config.namespace_name}"
  deploy_argo        = ${ns_config.deploy_argo}
  argo_namespace     = "${ns_config.argo_namespace}"
  argo_password      = var.argo_password
  argo_cluster_labels = {
    type = "tenant"
  }
  argo_project = "${ns_config.tenant_name}"
}

%{ endfor ~}
EOF
}

inputs = {
  argo_password = values.argo_password
}