terraform {
  # Backend type only — actual config passed at init time via -backend-config flag or TF_BACKEND_* env vars.
  # Local dev: terraform init -backend-config=backend-local.hcl  (or set BACKEND_CONFIG in Makefile)
  # CI: pass TF_BACKEND_* env vars or a backend config file via BACKEND_CONFIG secret.
  # Example backend-local.hcl:
  #   path = "terraform.tfstate"
  backend "local" {}
}
