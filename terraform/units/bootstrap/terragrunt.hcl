# Bootstrap unit - generates providers and module calls for all namespaces
# based on the output of the tenants unit

dependency "tenants" {
  config_path = values.tenants_path

  mock_outputs = {
    kubeconfigs = {}
    namespaces_config = {}
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

terraform {
  source = "../bootstrap-tenant"
}

# Generate providers for each namespace from tenants output
generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
      configuration_aliases = [
%{ for key, config in dependency.tenants.outputs.kubeconfigs ~}
        kubernetes.${replace(key, "-", "_")},
%{ endfor ~}
      ]
    }
  }
}

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
  path      = "main.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
%{ for key, ns_config in dependency.tenants.outputs.namespaces_config ~}
module "bootstrap_${replace(key, "-", "_")}" {
  source = "../bootstrap-tenant"

  providers = {
    kubernetes = kubernetes.${replace(key, "-", "_")}
  }

  namespace          = "${ns_config.namespace_name}"
  tenant_name        = "${ns_config.tenant_name}"
  deploy_argo        = ${ns_config.deploy_argo}
  argo_namespace     = "${ns_config.argo_namespace}"
  argo_password      = var.argo_password
  argo_cluster_labels = {
    type = "tenant"
  }
}

%{ endfor ~}
EOF
}

# Generate variables
generate "variables" {
  path      = "variables.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
variable "argo_password" {
  type      = string
  sensitive = true
  default   = ""
}
EOF
}

inputs = {
  argo_password = get_env("TF_VAR_argo_password", "")
}
