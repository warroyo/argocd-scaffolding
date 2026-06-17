# Renders, from the live state-namespace credentials, the two gitignored files the
# infra/bootstrap Kubernetes backends need:
#
#   .kube-backend.config  — a kubeconfig (server + token). Each root's backend.tf points
#                           config_path at it; the backend reads the host and token here.
#   .kube-backend.env     — KUBE_NAMESPACE. The kubernetes backend only takes host/token from
#                           the kubeconfig — the target namespace is NOT read from it, so it
#                           must be supplied as an env var. The Makefile sources this into
#                           every recipe.
#
# Splitting it this way is what testing showed actually works: a kubeconfig for auth (the
# individual KUBE_HOST/KUBE_TOKEN were not reliably honored by `terraform init`) plus the
# namespace direct. config_path, insecure, and secret_suffix are literals in each backend.tf.
#
# Both files hold a token / point at one — gitignored, never commit.

resource "local_sensitive_file" "backend_kubeconfig" {
  filename        = "${path.module}/../../.kube-backend.config"
  file_permission = "0600"
  content         = <<-EOT
    apiVersion: v1
    kind: Config
    clusters:
      - name: state-backend
        cluster:
          server: ${data.vcfa_kubeconfig.state.host}
          insecure-skip-tls-verify: ${data.vcfa_kubeconfig.state.insecure_skip_tls_verify}
    users:
      - name: state-backend
        user:
          token: ${data.vcfa_kubeconfig.state.token}
    contexts:
      - name: state-backend
        context:
          cluster: state-backend
          user: state-backend
          namespace: ${var.namespace}
    current-context: state-backend
  EOT
}

resource "local_sensitive_file" "backend_env" {
  filename        = "${path.module}/../../.kube-backend.env"
  file_permission = "0600"
  content         = <<-EOT
    export KUBE_NAMESPACE='${var.namespace}'
  EOT
}
