# Renders a gitignored env file with the live state-namespace credentials as the
# Kubernetes backend's environment variables (KUBE_HOST/KUBE_TOKEN/KUBE_INSECURE/
# KUBE_NAMESPACE). The Makefile sources this into every recipe (see scripts/load-env.sh),
# so infra/bootstrap init+apply reach the backend. Credentials stay in the environment —
# never in -backend-config, .terraform, or plan files. `secret_suffix` is the only
# backend setting that can't come from an env var; it's a literal in each root's backend.tf.
#
# Contains a token — gitignored, never commit.

resource "local_sensitive_file" "backend_env" {
  filename        = "${path.module}/../../.kube-backend.env"
  file_permission = "0600"
  content         = <<-EOT
    export KUBE_HOST='${data.vcfa_kubeconfig.state.host}'
    export KUBE_TOKEN='${data.vcfa_kubeconfig.state.token}'
    export KUBE_INSECURE='${data.vcfa_kubeconfig.state.insecure_skip_tls_verify}'
    export KUBE_NAMESPACE='${var.namespace}'
  EOT
}
