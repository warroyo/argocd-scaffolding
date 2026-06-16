# Renders the gitignored `backend-k8s.hcl` for each consuming root. Each carries the
# live host/token plus a distinct secret_suffix, so terraform/infra and
# terraform/bootstrap store separate state Secrets in the one namespace.
#
# These files contain a token — they are gitignored and must not be committed.

locals {
  # Roots that store state in the namespace, keyed by their secret_suffix.
  state_consumers = {
    infra     = "${path.module}/../infra/backend-k8s.hcl"
    bootstrap = "${path.module}/../bootstrap/backend-k8s.hcl"
  }
}

resource "local_sensitive_file" "backend_config" {
  for_each        = local.state_consumers
  filename        = each.value
  file_permission = "0600"
  content         = <<-EOT
    host          = "${data.vcfa_kubeconfig.state.host}"
    token         = "${data.vcfa_kubeconfig.state.token}"
    insecure      = ${data.vcfa_kubeconfig.state.insecure_skip_tls_verify}
    namespace     = "${var.namespace}"
    secret_suffix = "${each.key}"
  EOT
}
