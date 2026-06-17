REPO_ROOT         := $(shell git rev-parse --show-toplevel)
INFRA_DIR         := $(REPO_ROOT)/terraform/infra
BOOTSTRAP_DIR     := $(REPO_ROOT)/terraform/bootstrap
STATE_BACKEND_DIR := $(REPO_ROOT)/terraform/state-backend

# Load a gitignored .env into EVERY recipe so all terraform roots — infra, bootstrap, AND
# state-backend — see the same vcfa creds (tfvars only apply to their own dir, which is why
# state-backend prompted for vars). Recipes run under bash, and bash auto-sources the file
# named by BASH_ENV for non-interactive shells — so scripts/load-env.sh sources .env with
# normal shell parsing (quotes, spaces, comments all handled). No var list, no duplication.
# Copy .env.example to .env and fill it in.
SHELL := bash
export ENV_FILE    := $(REPO_ROOT)/.env
export BASH_ENV    := $(REPO_ROOT)/scripts/load-env.sh

# Kubernetes backend creds (KUBE_HOST/KUBE_TOKEN/KUBE_INSECURE/KUBE_NAMESPACE) are rendered
# by `make state-backend` into this gitignored file and sourced into every recipe by
# load-env.sh — so terraform reaches the backend without secrets in -backend-config.
export BACKEND_ENV := $(REPO_ROOT)/.kube-backend.env

# Prefix for make-time $(shell) calls that read the k8s backend (they run under /bin/sh,
# which doesn't get BASH_ENV) — sources the KUBE_* creds first.
SRC_BACKEND := set -a; [ -f $(BACKEND_ENV) ] && . $(BACKEND_ENV); set +a;

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

## Refresh the state-namespace kubeconfig and render the (gitignored) .kube-backend.env
## (KUBE_* backend creds). Stateless helper — re-reads the kubeconfig live each run so the
## token is never stale. Requires the same vcfa TF_VAR_* as apply-infra and a populated
## terraform/state-backend/namespace.auto.tfvars (the one-time captured namespace name).
state-backend:
	terraform -chdir=$(STATE_BACKEND_DIR) init
	terraform -chdir=$(STATE_BACKEND_DIR) apply -auto-approve

# ── Infra module ───────────────────────────────────────────────────────────────

init-infra: state-backend
	terraform -chdir=$(INFRA_DIR) init

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
	terraform -chdir=$(BOOTSTRAP_DIR) init

plan-bootstrap: init-bootstrap
	$(eval KUBECONFIGS := $(shell $(SRC_BACKEND) terraform -chdir=$(INFRA_DIR) output -json kubeconfigs))
	$(eval NS_CONFIG := $(shell $(SRC_BACKEND) terraform -chdir=$(INFRA_DIR) output -json namespace_config))
	@TF_VAR_kubeconfigs='$(KUBECONFIGS)' TF_VAR_namespace_config='$(NS_CONFIG)' \
	  terraform -chdir=$(BOOTSTRAP_DIR) plan

apply-bootstrap: init-bootstrap
	$(eval KUBECONFIGS := $(shell $(SRC_BACKEND) terraform -chdir=$(INFRA_DIR) output -json kubeconfigs))
	$(eval NS_CONFIG := $(shell $(SRC_BACKEND) terraform -chdir=$(INFRA_DIR) output -json namespace_config))
	@TF_VAR_kubeconfigs='$(KUBECONFIGS)' TF_VAR_namespace_config='$(NS_CONFIG)' \
	  terraform -chdir=$(BOOTSTRAP_DIR) apply

# ── Combined ───────────────────────────────────────────────────────────────────

## Full apply: infra first (provisions + renders all generated files),
## then bootstrap. Commit the files rendered by apply-infra before apply-bootstrap.
apply: apply-infra apply-bootstrap

## Destroy bootstrap first (helm releases), then infra (namespaces/projects).
destroy-bootstrap: init-bootstrap
	$(eval KUBECONFIGS := $(shell $(SRC_BACKEND) terraform -chdir=$(INFRA_DIR) output -json kubeconfigs))
	$(eval NS_CONFIG := $(shell $(SRC_BACKEND) terraform -chdir=$(INFRA_DIR) output -json namespace_config))
	@TF_VAR_kubeconfigs='$(KUBECONFIGS)' TF_VAR_namespace_config='$(NS_CONFIG)' \
	  terraform -chdir=$(BOOTSTRAP_DIR) destroy

destroy-infra: init-infra
	terraform -chdir=$(INFRA_DIR) destroy

## Destroy bootstrap fully (helm releases) BEFORE infra (namespaces/projects).
## Uses sequential sub-makes so the order holds even under `make -j` — infra must
## still exist while bootstrap is destroyed (bootstrap reads infra's kubeconfigs).
destroy:
	$(MAKE) destroy-bootstrap
	$(MAKE) destroy-infra
