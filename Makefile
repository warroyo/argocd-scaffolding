REPO_ROOT     := $(shell git rev-parse --show-toplevel)
INFRA_DIR     := $(REPO_ROOT)/terraform/infra
BOOTSTRAP_DIR := $(REPO_ROOT)/terraform/bootstrap

# Sensitive variables — set these in your environment before running:
#
#   export TF_VAR_vcfa_refresh_token=...
#   export TF_VAR_argo_password=...
#   export TF_VAR_ako_username=...
#   export TF_VAR_ako_password=...
#   export TF_VAR_ako_ca_data=...
#
# Non-sensitive variables can be set in a terraform.tfvars file (gitignored)
# placed inside terraform/infra/ and terraform/bootstrap/ respectively,
# or passed via additional TF_VAR_* exports.

.PHONY: generate \
        init-infra plan-infra apply-infra output-infra \
        init-bootstrap plan-bootstrap apply-bootstrap \
        apply destroy-bootstrap destroy-infra

# ── Code generation ────────────────────────────────────────────────────────────

## Regenerate terraform/bootstrap/providers.tf and main.tf from tenants.yaml.
## Run this after every change to terraform/infra/tenants.yaml.
generate:
	@echo "==> Generating bootstrap Terraform files..."
	python3 $(REPO_ROOT)/scripts/generate-bootstrap.py

# ── Infra module ───────────────────────────────────────────────────────────────

init-infra:
	terraform -chdir=$(INFRA_DIR) init

plan-infra: init-infra
	terraform -chdir=$(INFRA_DIR) plan

apply-infra: init-infra generate
	terraform -chdir=$(INFRA_DIR) apply

## Print the kubeconfigs output (sensitive — not shown in plain text by default).
output-infra: init-infra
	terraform -chdir=$(INFRA_DIR) output -json kubeconfigs

# ── Bootstrap module ───────────────────────────────────────────────────────────

init-bootstrap: generate
	terraform -chdir=$(BOOTSTRAP_DIR) init

plan-bootstrap: init-bootstrap
	$(eval KUBECONFIGS := $(shell terraform -chdir=$(INFRA_DIR) output -json kubeconfigs))
	@TF_VAR_kubeconfigs='$(KUBECONFIGS)' \
	  terraform -chdir=$(BOOTSTRAP_DIR) plan

apply-bootstrap: init-bootstrap
	$(eval KUBECONFIGS := $(shell terraform -chdir=$(INFRA_DIR) output -json kubeconfigs))
	@TF_VAR_kubeconfigs='$(KUBECONFIGS)' \
	  terraform -chdir=$(BOOTSTRAP_DIR) apply

# ── Combined ───────────────────────────────────────────────────────────────────

## Full apply: infra first, then bootstrap.
apply: apply-infra apply-bootstrap

## Destroy bootstrap first (helm releases), then infra (namespaces/projects).
destroy-bootstrap: init-bootstrap
	$(eval KUBECONFIGS := $(shell terraform -chdir=$(INFRA_DIR) output -json kubeconfigs))
	@TF_VAR_kubeconfigs='$(KUBECONFIGS)' \
	  terraform -chdir=$(BOOTSTRAP_DIR) destroy

destroy-infra: init-infra
	terraform -chdir=$(INFRA_DIR) destroy

destroy: destroy-bootstrap destroy-infra
