# Stateless helper: pull a fresh, namespace-scoped kubeconfig for the Terraform-state
# supervisor namespace. Re-read live on every apply, so the token is never stale.
# No resources are managed here — see generate.tf for the rendered backend configs.

data "vcfa_kubeconfig" "state" {
  project_name              = var.project_name
  supervisor_namespace_name = var.namespace
}
