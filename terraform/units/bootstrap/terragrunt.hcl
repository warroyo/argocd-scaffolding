# Bootstrap unit for a single namespace
# This is used as source for dynamically generated units in terragrunt.stack.hcl

dependency "tenants" {
  config_path = values.tenants_path

  mock_outputs = {
    kubeconfigs = {
      (values.namespace_key) = {
        host                     = "https://mock-host"
        token                    = "mock-token"
        insecure_skip_tls_verify = true
      }
    }
    namespaces_config = {
      (values.namespace_key) = {
        tenant_name    = "mock-tenant"
        namespace_name = "mock-namespace"
        deploy_argo    = true
        argo_namespace = "mock-argo-ns"
        project_id     = "mock-project-id"
      }
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

terraform {
  source = "../bootstrap-tenant"
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

provider "kubernetes" {
  host     = "${dependency.tenants.outputs.kubeconfigs[values.namespace_key].host}"
  token    = "${dependency.tenants.outputs.kubeconfigs[values.namespace_key].token}"
  insecure = ${dependency.tenants.outputs.kubeconfigs[values.namespace_key].insecure_skip_tls_verify}
}
EOF
}

inputs = {
  namespace          = dependency.tenants.outputs.namespaces_config[values.namespace_key].namespace_name
  tenant_name        = dependency.tenants.outputs.namespaces_config[values.namespace_key].tenant_name
  deploy_argo        = dependency.tenants.outputs.namespaces_config[values.namespace_key].deploy_argo
  argo_namespace     = dependency.tenants.outputs.namespaces_config[values.namespace_key].argo_namespace
  argo_password      = get_env("TF_VAR_argo_password", "")
  argo_cluster_labels = {
    type = "tenant"
  }
}

