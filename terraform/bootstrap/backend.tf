terraform {
  # State is stored as a Kubernetes Secret in the dedicated state supervisor namespace.
  # Backend config (host/token/namespace/secret_suffix) is rendered by the
  # terraform/state-backend helper into backend-k8s.hcl (gitignored) and supplied at init:
  #   make init-bootstrap    (auto-runs `make state-backend`, then init -backend-config=backend-k8s.hcl)
  # First migration from prior local state:
  #   terraform -chdir=terraform/bootstrap init -migrate-state -backend-config=backend-k8s.hcl
  backend "kubernetes" {}
}
