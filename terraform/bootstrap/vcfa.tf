# Bootstrap mints its own per-namespace tokens instead of consuming a
# kubeconfigs output shuttled from the infra run. vcfa kubeconfig tokens are
# short-lived; reading them live here (like terraform/state-backend does for the
# backend) means every plan/apply/destroy gets a fresh token — no
# refresh-infra-kubeconfigs step, no TF_VAR_kubeconfigs env shuttle.
#
# The project + suffixed namespace names come from var.namespace_config (the
# single infra -> bootstrap contract). The generated providers.tf references
# data.vcfa_kubeconfig.ns["<key>"] per helm provider.

provider "vcfa" {
  url                  = var.vcfa_url
  allow_unverified_ssl = true
  org                  = var.vcfa_org
  auth_type            = "api_token"
  api_token            = var.vcfa_refresh_token
}

data "vcfa_kubeconfig" "ns" {
  for_each = var.namespace_config

  project_name              = each.value.tenant_name
  supervisor_namespace_name = each.value.namespace
}
