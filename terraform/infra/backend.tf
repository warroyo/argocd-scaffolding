terraform {
  # State is stored as a Kubernetes Secret in the dedicated state supervisor namespace.
  # Credentials come from the generated .kube-backend.config kubeconfig, which the Makefile
  # points KUBECONFIG at (see terraform/state-backend). The state namespace is the kubeconfig
  # context's namespace. secret_suffix can't come from the kubeconfig, so it's a literal here.
  backend "kubernetes" {
    secret_suffix = "infra"
  }
}
