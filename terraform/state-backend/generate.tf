# Renders the two gitignored files the kubernetes backends need (see the CLAUDE.md
# generated-files table): .kube-backend.config (kubeconfig with host + token, via
# each backend.tf config_path) and .kube-backend.env (KUBE_NAMESPACE — the backend
# doesn't read the namespace from the kubeconfig, so the Makefile sources it).
# Both hold/point at a token — never commit.

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
