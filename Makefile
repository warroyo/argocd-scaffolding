REPO_ROOT         := $(shell git rev-parse --show-toplevel)
INFRA_DIR         := $(REPO_ROOT)/terraform/infra
BOOTSTRAP_DIR     := $(REPO_ROOT)/terraform/bootstrap
STATE_BACKEND_DIR := $(REPO_ROOT)/terraform/state-backend

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

.PHONY: validate state-backend \
        init-infra plan-infra apply-infra output-infra \
        init-bootstrap plan-bootstrap apply-bootstrap \
        apply destroy-bootstrap destroy-infra destroy

# All config generation now happens inside the infra Terraform run (local_file):
# ArgoCD AppProjects, the tenant-vars handoff, and the bootstrap providers/main.tf
# wiring consumed by the second run. There is no separate generate step.

# ── Local testing ────────────────────────────────────────────────────────────────

## Build-test every kustomize entrypoint locally (same script CI runs). Requires kustomize.
validate:
	@$(REPO_ROOT)/scripts/validate.sh

# ── State backend ────────────────────────────────────────────────────────────────

## Refresh the state-namespace kubeconfig and render the (gitignored) backend-k8s.hcl
## for infra + bootstrap. Stateless helper — re-reads the kubeconfig live each run so the
## token is never stale. Requires the same vcfa TF_VAR_* as apply-infra and a populated
## terraform/state-backend/namespace.auto.tfvars (the one-time captured namespace name).
state-backend:
	terraform -chdir=$(STATE_BACKEND_DIR) init
	terraform -chdir=$(STATE_BACKEND_DIR) apply -auto-approve

# ── Infra module ───────────────────────────────────────────────────────────────

init-infra: state-backend
	terraform -chdir=$(INFRA_DIR) init \
	  -backend-config=$(if $(BACKEND_CONFIG),$(BACKEND_CONFIG),$(INFRA_DIR)/backend-k8s.hcl)

plan-infra: init-infra
	terraform -chdir=$(INFRA_DIR) plan

## Provisions namespaces and renders all generated config (AppProjects,
## tenant-vars, and terraform/bootstrap/{providers,main}.tf). Commit the result.
apply-infra: init-infra
	terraform -chdir=$(INFRA_DIR) apply

## Print the kubeconfigs output (sensitive — not shown in plain text by default).
output-infra: init-infra
	terraform -chdir=$(INFRA_DIR) output -json kubeconfigs

# ── Bootstrap module ───────────────────────────────────────────────────────────

init-bootstrap: state-backend
	terraform -chdir=$(BOOTSTRAP_DIR) init \
	  -backend-config=$(if $(BACKEND_CONFIG),$(BACKEND_CONFIG),$(BOOTSTRAP_DIR)/backend-k8s.hcl)

plan-bootstrap: init-bootstrap
	$(eval KUBECONFIGS := $(shell terraform -chdir=$(INFRA_DIR) output -json kubeconfigs))
	$(eval NS_CONFIG := $(shell terraform -chdir=$(INFRA_DIR) output -json namespace_config))
	@TF_VAR_kubeconfigs='$(KUBECONFIGS)' TF_VAR_namespace_config='$(NS_CONFIG)' \
	  terraform -chdir=$(BOOTSTRAP_DIR) plan

apply-bootstrap: init-bootstrap
	$(eval KUBECONFIGS := $(shell terraform -chdir=$(INFRA_DIR) output -json kubeconfigs))
	$(eval NS_CONFIG := $(shell terraform -chdir=$(INFRA_DIR) output -json namespace_config))
	@TF_VAR_kubeconfigs='$(KUBECONFIGS)' TF_VAR_namespace_config='$(NS_CONFIG)' \
	  terraform -chdir=$(BOOTSTRAP_DIR) apply

# ── Combined ───────────────────────────────────────────────────────────────────

## Full apply: infra first (provisions + renders all generated files),
## then bootstrap. Commit the files rendered by apply-infra before apply-bootstrap.
apply: apply-infra apply-bootstrap

## Destroy bootstrap first (helm releases), then infra (namespaces/projects).
destroy-bootstrap: init-bootstrap
	$(eval KUBECONFIGS := $(shell terraform -chdir=$(INFRA_DIR) output -json kubeconfigs))
	$(eval NS_CONFIG := $(shell terraform -chdir=$(INFRA_DIR) output -json namespace_config))
	@TF_VAR_kubeconfigs='$(KUBECONFIGS)' TF_VAR_namespace_config='$(NS_CONFIG)' \
	  terraform -chdir=$(BOOTSTRAP_DIR) destroy

destroy-infra: init-infra
	terraform -chdir=$(INFRA_DIR) destroy

destroy: destroy-bootstrap destroy-infra
