terraform {
  # State is stored as a Kubernetes Secret in the dedicated state supervisor namespace.
  # Host + token come from the generated .kube-backend.config kubeconfig (rendered by
  # terraform/state-backend; gitignored). config_path is relative to this root dir under
  # `-chdir`, so ../../ is the repo root. The backend does NOT read the target namespace from
  # the kubeconfig, so it comes from KUBE_NAMESPACE (.kube-backend.env, sourced by the Makefile).
  backend "kubernetes" {
    secret_suffix = "bootstrap"
    config_path   = "../../.kube-backend.config"
    insecure      = true
  }
}
