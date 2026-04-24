REPO_ROOT     := $(shell git rev-parse --show-toplevel)
INFRA_DIR     := $(REPO_ROOT)/terraform/infra
BOOTSTRAP_DIR := $(REPO_ROOT)/terraform/bootstrap
GENERATE_DIR  := $(REPO_ROOT)/terraform/generate

# Sensitive variables — set these in your environment before running:
#
#   export TF_VAR_vcfa_refresh_token=...
#   export TF_VAR_argo_password=...
#   export TF_VAR_ako_username=...
#   export TF_VAR_ako_password=...
#   export TF_VAR_ako_ca_data=...
#   export TF_VAR_repo_url=https://github.com/your-org/argocd-scaffolding
#
# Non-sensitive variables can be set in a terraform.tfvars file (gitignored)
# placed inside terraform/infra/ and terraform/bootstrap/ respectively,
# or passed via additional TF_VAR_* exports.
#
# Backend config (local dev):
#   Create terraform/infra/backend-local.hcl with: path = "terraform.tfstate"
#   Then: make apply-infra BACKEND_CONFIG=terraform/infra/backend-local.hcl
# Backend config (CI): pass via BACKEND_CONFIG env var pointing to a config file,
#   or set TF_BACKEND_* env vars understood by the chosen backend.

BACKEND_CONFIG ?=

.PHONY: generate \
        init-infra plan-infra apply-infra output-infra \
        init-bootstrap plan-bootstrap apply-bootstrap \
        apply destroy-bootstrap destroy-infra destroy

# ── Code generation ────────────────────────────────────────────────────────────

## Regenerate all static configs from source YAML (tenants.yaml).
## Run this after every change to terraform/infra/tenants.yaml.
generate:
	@echo "==> Generating bootstrap Terraform files..."
	python3 $(REPO_ROOT)/scripts/generate-bootstrap.py
	@echo "==> Generating ArgoCD projects and tenant dirs..."
	terraform -chdir=$(GENERATE_DIR) init -upgrade -input=false
	terraform -chdir=$(GENERATE_DIR) apply -auto-approve -input=false

# ── Infra module ───────────────────────────────────────────────────────────────

init-infra:
	terraform -chdir=$(INFRA_DIR) init \
	  $(if $(BACKEND_CONFIG),-backend-config=$(BACKEND_CONFIG),)

plan-infra: init-infra
	terraform -chdir=$(INFRA_DIR) plan

apply-infra: init-infra generate
	terraform -chdir=$(INFRA_DIR) apply

## Print the kubeconfigs output (sensitive — not shown in plain text by default).
output-infra: init-infra
	terraform -chdir=$(INFRA_DIR) output -json kubeconfigs

# ── Bootstrap module ───────────────────────────────────────────────────────────

init-bootstrap: generate
	terraform -chdir=$(BOOTSTRAP_DIR) init \
	  $(if $(BACKEND_CONFIG),-backend-config=$(BACKEND_CONFIG),)

plan-bootstrap: init-bootstrap
	$(eval KUBECONFIGS := $(shell terraform -chdir=$(INFRA_DIR) output -json kubeconfigs))
	@TF_VAR_kubeconfigs='$(KUBECONFIGS)' \
	  terraform -chdir=$(BOOTSTRAP_DIR) plan

apply-bootstrap: init-bootstrap
	$(eval KUBECONFIGS := $(shell terraform -chdir=$(INFRA_DIR) output -json kubeconfigs))
	@TF_VAR_kubeconfigs='$(KUBECONFIGS)' \
	  terraform -chdir=$(BOOTSTRAP_DIR) apply

# ── Combined ───────────────────────────────────────────────────────────────────

## Full apply: infra first (includes generate + namespace-details/tenant-vars via TF), then bootstrap.
apply: apply-infra apply-bootstrap

## Destroy bootstrap first (helm releases), then infra (namespaces/projects).
destroy-bootstrap: init-bootstrap
	$(eval KUBECONFIGS := $(shell terraform -chdir=$(INFRA_DIR) output -json kubeconfigs))
	@TF_VAR_kubeconfigs='$(KUBECONFIGS)' \
	  terraform -chdir=$(BOOTSTRAP_DIR) destroy

destroy-infra: init-infra
	terraform -chdir=$(INFRA_DIR) destroy

destroy: destroy-bootstrap destroy-infra
