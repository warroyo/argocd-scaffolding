# Renders a gitignored kubeconfig with the live state-namespace credentials. The Makefile
# points the KUBECONFIG env var at this file for every recipe, so the infra/bootstrap
# Kubernetes backends authenticate from it. Testing showed the individual KUBE_* env vars
# (KUBE_HOST/KUBE_TOKEN/KUBE_INSECURE/KUBE_NAMESPACE) were not reliably honored by
# `terraform init`; a kubeconfig referenced via KUBECONFIG is. The state namespace is the
# context's namespace, so the backend writes its Secret there. Credentials stay on disk in
# this gitignored file — never in -backend-config, .terraform, or plan files. `secret_suffix`
# is the only backend setting that can't come from the kubeconfig; it's a literal in each
# root's backend.tf.
#
# Contains a token — gitignored, never commit.

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
