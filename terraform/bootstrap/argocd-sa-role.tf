# Grants each ArgoCD instance's VCFA service account the "ArgoCD Instance" org
# role, which the operator's API path leaves empty (the UI adds it). Without it
# every ManagedEntity fails "No assigned roles". See docs/DECISIONS.md #25.
# VCFA credentials stay out of state: ephemeral reads + write-only PUT.

locals {
  argocd_instance_name = yamldecode(file("${path.module}/../../charts/bootstrap-tenant/values.yaml")).argoInstance.name
  argocd_role_name     = "ArgoCD Instance"
  vcfa_api             = trimsuffix(var.vcfa_url, "/")
  vcfa_accept          = "application/json;version=40.0"
}

# Wait: the operator's SA secret 404s until the VCFA account exists, and lands
# alongside status.serviceAccounts. TerraCurl can only retry on status codes.
resource "terracurl_request" "argocd_sa_ready" {
  for_each = local.argo_namespaces

  name               = "argocd-sa-ready-${each.value.namespace}"
  method             = "GET"
  url                = "${data.vcfa_kubeconfig.ns[each.key].host}/api/v1/namespaces/${each.value.namespace}/secrets/${local.argocd_instance_name}-argocd-vcfa-sa-secret"
  headers_wo         = { Authorization = "Bearer ${data.vcfa_kubeconfig.ns[each.key].token}" }
  headers_wo_version = 1
  skip_tls_verify    = data.vcfa_kubeconfig.ns[each.key].insecure_skip_tls_verify
  response_codes     = ["200"]
  response_sensitive = true
  max_retry          = 60
  retry_interval     = 10
  skip_destroy       = true
}

data "terracurl_request" "argocd_cr" {
  for_each   = local.argo_namespaces
  depends_on = [terracurl_request.argocd_sa_ready]

  name            = "argocd-cr-${each.value.namespace}"
  method          = "GET"
  url             = "${data.vcfa_kubeconfig.ns[each.key].host}/apis/argocd-service.vsphere.vmware.com/v1alpha1/namespaces/${each.value.namespace}/argocds/${local.argocd_instance_name}"
  headers         = { Authorization = "Bearer ${data.vcfa_kubeconfig.ns[each.key].token}" }
  skip_tls_verify = data.vcfa_kubeconfig.ns[each.key].insecure_skip_tls_verify
  response_codes  = ["200"]

  lifecycle {
    postcondition {
      condition     = try(jsondecode(self.response).status.serviceAccounts.platform.id, "") != ""
      error_message = "ArgoCD ${each.value.namespace}/${local.argocd_instance_name} has no status.serviceAccounts.platform.id yet; re-run make apply-bootstrap."
    }
  }
}

locals {
  argocd_sa_id = { for k, d in data.terracurl_request.argocd_cr : k => jsondecode(d.response).status.serviceAccounts.platform.id }
}

# Org-admin session from the refresh token Terraform already uses.
ephemeral "terracurl_request" "vcfa_token" {
  count = length(local.argo_namespaces) > 0 ? 1 : 0

  name               = "vcfa-token"
  method             = "POST"
  url                = "${local.vcfa_api}/oauth/tenant/${var.vcfa_org}/token"
  headers            = { "Content-Type" = "application/x-www-form-urlencoded" }
  request_body       = "grant_type=refresh_token&refresh_token=${var.vcfa_refresh_token}"
  skip_tls_verify    = true
  response_codes     = ["200"]
  response_sensitive = true
  skip_renew         = true
  skip_close         = true
}

locals {
  vcfa_headers = length(ephemeral.terracurl_request.vcfa_token) == 0 ? {} : {
    Authorization = "Bearer ${jsondecode(ephemeral.terracurl_request.vcfa_token[0].sensitive_response).access_token}"
    Accept        = local.vcfa_accept
  }
}

ephemeral "terracurl_request" "argocd_role" {
  count = length(local.argo_namespaces) > 0 ? 1 : 0

  name               = "vcfa-role"
  method             = "GET"
  url                = "${local.vcfa_api}/cloudapi/1.0.0/roles"
  request_parameters = { filter = "name==${local.argocd_role_name}" }
  headers            = local.vcfa_headers
  skip_tls_verify    = true
  response_codes     = ["200"]
  skip_renew         = true
  skip_close         = true
}

ephemeral "terracurl_request" "argocd_sa" {
  for_each = local.argo_namespaces

  name            = "vcfa-sa-${each.value.namespace}"
  method          = "GET"
  url             = "${local.vcfa_api}/cloudapi/1.0.0/serviceAccounts/${local.argocd_sa_id[each.key]}"
  headers         = local.vcfa_headers
  skip_tls_verify = true
  response_codes  = ["200"]
  skip_renew      = true
  skip_close      = true
}

locals {
  argocd_role = length(ephemeral.terracurl_request.argocd_role) == 0 ? null : {
    name = jsondecode(ephemeral.terracurl_request.argocd_role[0].response).values[0].name
    id   = jsondecode(ephemeral.terracurl_request.argocd_role[0].response).values[0].id
  }
}

# Re-PUT whenever the instance's account changes (request_body_wo_version).
# Destroy is a no-op: the account belongs to the operator.
resource "terracurl_request" "argocd_sa_role" {
  for_each = local.argo_namespaces

  name       = "argocd-sa-role-${each.value.namespace}"
  method     = "PUT"
  url        = "${local.vcfa_api}/cloudapi/1.0.0/serviceAccounts/${local.argocd_sa_id[each.key]}"
  headers_wo = merge(local.vcfa_headers, { "Content-Type" = "application/json" })
  request_body_wo = jsonencode(merge(jsondecode(ephemeral.terracurl_request.argocd_sa[each.key].response), {
    roles = concat(
      [for r in jsondecode(ephemeral.terracurl_request.argocd_sa[each.key].response).roles : r if r.id != local.argocd_role.id],
      [local.argocd_role],
    )
  }))
  request_body_wo_version = parseint(substr(sha1(local.argocd_sa_id[each.key]), 0, 8), 16)
  headers_wo_version      = parseint(substr(sha1(local.argocd_sa_id[each.key]), 0, 8), 16)
  skip_tls_verify         = true
  response_codes          = ["200"]
  skip_destroy            = true
}
