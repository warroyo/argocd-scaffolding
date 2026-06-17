terraform {
  # State is stored as a Kubernetes Secret in the dedicated state supervisor namespace.
  # Credentials come from KUBE_HOST/KUBE_TOKEN/KUBE_INSECURE/KUBE_NAMESPACE env vars, which
  # the Makefile sources from the generated .kube-backend.env (see terraform/state-backend).
  # secret_suffix can't be an env var, so it's a literal here.
  backend "kubernetes" {
    secret_suffix = "infra"
  }
}
