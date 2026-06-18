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

# Kubernetes backend creds: `make state-backend` renders two gitignored files from the live
# state-namespace credentials. The kubeconfig (.kube-backend.config) carries host + token and
# each root's backend.tf points config_path at it (alongside literal insecure + secret_suffix).
# The backend does NOT read the target namespace from the kubeconfig, so it comes from
# KUBE_NAMESPACE in .kube-backend.env, sourced into every recipe by load-env.sh.
export BACKEND_ENV := $(REPO_ROOT)/.kube-backend.env

# Prefix for make-time $(shell) calls that read the k8s backend (they run under /bin/sh,
# which doesn't get BASH_ENV) — sources KUBE_NAMESPACE first.
SRC_BACKEND := set -a; [ -f $(BACKEND_ENV) ] && . $(BACKEND_ENV); set +a;

.PHONY: validate state-backend \
        init-infra plan-infra apply-infra output-infra \
        init-bootstrap refresh-infra-kubeconfigs plan-bootstrap apply-bootstrap \
        apply destroy-bootstrap destroy-infra destroy

# All config generation now happens inside the infra Terraform run (local_file):
# ArgoCD AppProjects, the tenant-vars handoff, and the bootstrap providers/main.tf
# wiring consumed by the second run. There is no separate generate step.

# ── Local testing ────────────────────────────────────────────────────────────────

## Build-test every kustomize entrypoint locally (same script CI runs). Requires kustomize.
validate:
	@$(REPO_ROOT)/scripts/validate.sh

# ── State backend ────────────────────────────────────────────────────────────────

## Refresh the state-namespace creds: render the (gitignored) .kube-backend.config kubeconfig
## (config_path in each backend.tf points at it) and .kube-backend.env (KUBE_NAMESPACE).
## Stateless helper — re-reads the kubeconfig live each run so the token is never stale.
## Requires the same vcfa TF_VAR_* as apply-infra and a populated
## terraform/state-backend/namespace.auto.tfvars (the one-time captured namespace name).
state-backend:
	terraform -chdir=$(STATE_BACKEND_DIR) init
	terraform -chdir=$(STATE_BACKEND_DIR) apply -auto-approve

# ── Infra module ───────────────────────────────────────────────────────────────

# -reconfigure: the kubernetes backend caches host+token in .terraform/terraform.tfstate at
# init. A plain re-init sees the backend *block* unchanged (config_path is the same path) and
# keeps the cached — now expired — token, even though state-backend just rewrote
# .kube-backend.config with a fresh one. -reconfigure discards the cached backend state and
# re-reads the kubeconfig, so the new token is always picked up.
init-infra: state-backend
	terraform -chdir=$(INFRA_DIR) init -reconfigure

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
	terraform -chdir=$(BOOTSTRAP_DIR) init -reconfigure

# The bootstrap helm providers authenticate with the per-namespace tokens carried in infra's
# `kubeconfigs` output. vcfa kubeconfig tokens are short-lived, and `terraform output` reads
# STATE ONLY — it does not re-read the data.vcfa_kubeconfig data sources — so the output serves
# whatever token was captured at the last infra apply, which may be long expired. Re-read the
# data sources into infra state first so every bootstrap recipe below gets a fresh token. This
# is why `make apply` (which applies infra first) worked while a standalone `make apply-bootstrap`
# authenticated with a stale token.
refresh-infra-kubeconfigs: init-infra
	terraform -chdir=$(INFRA_DIR) apply -refresh-only -auto-approve

plan-bootstrap: init-bootstrap refresh-infra-kubeconfigs
	$(eval KUBECONFIGS := $(shell $(SRC_BACKEND) terraform -chdir=$(INFRA_DIR) output -json kubeconfigs))
	$(eval NS_CONFIG := $(shell $(SRC_BACKEND) terraform -chdir=$(INFRA_DIR) output -json namespace_config))
	@TF_VAR_kubeconfigs='$(KUBECONFIGS)' TF_VAR_namespace_config='$(NS_CONFIG)' \
	  terraform -chdir=$(BOOTSTRAP_DIR) plan

apply-bootstrap: init-bootstrap refresh-infra-kubeconfigs
	$(eval KUBECONFIGS := $(shell $(SRC_BACKEND) terraform -chdir=$(INFRA_DIR) output -json kubeconfigs))
	$(eval NS_CONFIG := $(shell $(SRC_BACKEND) terraform -chdir=$(INFRA_DIR) output -json namespace_config))
	@TF_VAR_kubeconfigs='$(KUBECONFIGS)' TF_VAR_namespace_config='$(NS_CONFIG)' \
	  terraform -chdir=$(BOOTSTRAP_DIR) apply

# ── Combined ───────────────────────────────────────────────────────────────────

## Full apply: infra first (provisions + renders all generated files),
## then bootstrap. Commit the files rendered by apply-infra before apply-bootstrap.
apply: apply-infra apply-bootstrap

## Destroy bootstrap first (helm releases), then infra (namespaces/projects).
destroy-bootstrap: init-bootstrap refresh-infra-kubeconfigs
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
