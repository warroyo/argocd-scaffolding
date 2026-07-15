REPO_ROOT         := $(shell git rev-parse --show-toplevel)
INFRA_DIR         := $(REPO_ROOT)/terraform/infra
BOOTSTRAP_DIR     := $(REPO_ROOT)/terraform/bootstrap
STATE_BACKEND_DIR := $(REPO_ROOT)/terraform/state-backend

# Extra flags for `terraform apply`. Empty locally (interactive approval); CI
# sets TF_APPLY_FLAGS=-auto-approve -input=false (there is no TTY to approve on).
TF_APPLY_FLAGS ?=

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

# Paths rendered by apply-infra that ArgoCD consumes from git. apply-bootstrap
# refuses to run while these are dirty — otherwise the helm bootstrap succeeds
# but ArgoCD syncs a main that lacks the new AppProjects / tenant-vars.
GENERATED_PATHS := argocd/projects 'infrastructure/clusters/*/vars' \
                   terraform/bootstrap/providers.tf terraform/bootstrap/main.tf

.PHONY: validate state-backend check-generated-clean \
        init-infra plan-infra apply-infra \
        init-bootstrap plan-bootstrap apply-bootstrap \
        apply destroy-apps destroy-bootstrap destroy-infra destroy \
        shell

# ROOT=<infra|bootstrap> → the terraform dir, for the `shell` helper.
TF_ROOT_DIR := $(if $(filter infra,$(ROOT)),$(INFRA_DIR),$(if $(filter bootstrap,$(ROOT)),$(BOOTSTRAP_DIR),))

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
	terraform -chdir=$(INFRA_DIR) apply $(TF_APPLY_FLAGS)

# ── Bootstrap module ───────────────────────────────────────────────────────────

# Bootstrap mints its own per-namespace tokens (data.vcfa_kubeconfig in
# terraform/bootstrap/vcfa.tf), so there is no kubeconfigs shuttle from infra and
# no refresh-only step — only the structural namespace_config output is passed.

init-bootstrap: state-backend
	terraform -chdir=$(BOOTSTRAP_DIR) init -reconfigure

## Fail if apply-infra rendered files that aren't committed yet — ArgoCD reads git,
## so bootstrapping ahead of the commit hands it stale config. Set
## SKIP_GENERATED_CHECK=1 to override deliberately.
check-generated-clean:
	@if [ -z "$$SKIP_GENERATED_CHECK" ] && [ -n "$$(git status --porcelain -- $(GENERATED_PATHS))" ]; then \
	  echo "error: generated files are uncommitted (rendered by apply-infra):" >&2; \
	  git status --short -- $(GENERATED_PATHS) >&2; \
	  echo "Commit them first (or set SKIP_GENERATED_CHECK=1)." >&2; \
	  exit 1; \
	fi

plan-bootstrap: init-bootstrap
	$(eval NS_CONFIG := $(shell $(SRC_BACKEND) terraform -chdir=$(INFRA_DIR) output -json namespace_config))
	@TF_VAR_namespace_config='$(NS_CONFIG)' \
	  terraform -chdir=$(BOOTSTRAP_DIR) plan

apply-bootstrap: check-generated-clean init-bootstrap
	$(eval NS_CONFIG := $(shell $(SRC_BACKEND) terraform -chdir=$(INFRA_DIR) output -json namespace_config))
	@TF_VAR_namespace_config='$(NS_CONFIG)' \
	  terraform -chdir=$(BOOTSTRAP_DIR) apply $(TF_APPLY_FLAGS)

# ── Combined ───────────────────────────────────────────────────────────────────

## Full apply: infra first (provisions + renders all generated files),
## then bootstrap. Commit the files rendered by apply-infra before apply-bootstrap
## (apply-bootstrap enforces this via check-generated-clean).
apply: apply-infra apply-bootstrap

## Destroy bootstrap first (helm releases), then infra (namespaces/projects).
destroy-bootstrap: init-bootstrap
	$(eval NS_CONFIG := $(shell $(SRC_BACKEND) terraform -chdir=$(INFRA_DIR) output -json namespace_config 2>/dev/null))
	@if [ -z '$(NS_CONFIG)' ]; then \
	  echo "error: infra output 'namespace_config' is empty or absent." >&2; \
	  echo "  Infra state carries no outputs — infra was never fully applied (a partial" >&2; \
	  echo "  apply-infra leaves no outputs) or is already destroyed." >&2; \
	  echo "  Bootstrap destroy needs it to auth its per-namespace providers, so it cannot run." >&2; \
	  echo "  If nothing was bootstrapped, skip this step: make destroy-infra" >&2; \
	  echo "  If bootstrap state is orphaned, clear it directly: terraform -chdir=$(BOOTSTRAP_DIR) state list" >&2; \
	  exit 1; \
	fi
	@TF_VAR_namespace_config='$(NS_CONFIG)' \
	  terraform -chdir=$(BOOTSTRAP_DIR) destroy

destroy-infra: init-infra
	terraform -chdir=$(INFRA_DIR) destroy

## Delete ArgoCD-managed ApplicationSets + Applications and let their finalizers
## cascade (removing the VKS workload clusters) BEFORE ArgoCD is torn down. Those
## Applications are appset-generated (not helm-owned), so destroy-bootstrap alone
## orphans them and leaks clusters. Talks to the vcfa supervisor (where ArgoCD runs)
## via a throwaway kubeconfig built from bootstrap's argo_endpoints output — no ambient
## kubectl context needed. A refresh-only pass first re-reads the vcfa data source so
## the short-lived tokens are fresh. It is split into `plan -refresh-only -out` (var via
## env) + `apply <planfile>` (no var): the helm providers configure host/token from
## data.vcfa_kubeconfig, so a single-shot `apply -refresh-only` splits internally into
## plan+apply and the still-set TF_VAR_namespace_config trips Terraform's "can't set a
## variable when applying a saved plan" guard. Baking the var into the plan file avoids it.
## Requires kubectl + jq. Only deploy_argo namespaces.
destroy-apps: init-bootstrap
	$(eval NS_CONFIG := $(shell $(SRC_BACKEND) terraform -chdir=$(INFRA_DIR) output -json namespace_config 2>/dev/null))
	@if [ -z '$(NS_CONFIG)' ]; then echo "warn: infra namespace_config empty — nothing to clean, skipping." >&2; exit 0; fi
	@echo "refreshing ArgoCD-namespace tokens..."
	@tfp=$$(mktemp) && \
	  TF_VAR_namespace_config='$(NS_CONFIG)' terraform -chdir=$(BOOTSTRAP_DIR) plan -refresh-only -out="$$tfp" >/dev/null && \
	  terraform -chdir=$(BOOTSTRAP_DIR) apply -input=false "$$tfp" >/dev/null; \
	  rc=$$?; rm -f "$$tfp"; exit $$rc
	@umask 077; tmp=$$(mktemp -d); trap 'rm -rf "$$tmp"' EXIT; \
	  eps=$$(TF_VAR_namespace_config='$(NS_CONFIG)' terraform -chdir=$(BOOTSTRAP_DIR) output -json argo_endpoints); \
	  if [ "$$(jq 'length' <<<"$$eps")" = 0 ]; then echo "no deploy_argo namespaces — nothing to clean."; exit 0; fi; \
	  jq -c 'to_entries[]' <<<"$$eps" | while read -r e; do \
	    ns=$$(jq -r '.key' <<<"$$e"); kc="$$tmp/$$ns"; \
	    jq -r '.value | "apiVersion: v1\nkind: Config\nclusters:\n- name: a\n  cluster:\n    server: \(.host)\n    insecure-skip-tls-verify: \(.insecure)\nusers:\n- name: a\n  user:\n    token: \(.token)\ncontexts:\n- name: a\n  context:\n    cluster: a\n    user: a\n    namespace: \(.namespace)\ncurrent-context: a"' <<<"$$e" > "$$kc"; \
	    echo "== $$ns: deleting ApplicationSets + Applications (cascades cluster deletion; up to 25m) =="; \
	    kubectl --kubeconfig="$$kc" delete applicationset --all --ignore-not-found || true; \
	    kubectl --kubeconfig="$$kc" delete application    --all --ignore-not-found --wait --timeout=25m || true; \
	  done

## Full teardown in the correct order: (1) drain ArgoCD-managed apps so clusters
## cascade-delete while ArgoCD lives, (2) destroy bootstrap (helm/ArgoCD), (3) destroy
## infra (namespaces/projects). Sequential sub-makes so the order holds even under
## `make -j` — infra must still exist while bootstrap is destroyed (bootstrap mints
## tokens against the still-existing namespaces and reads infra's namespace_config).
destroy:
	$(MAKE) destroy-apps
	$(MAKE) destroy-bootstrap
	$(MAKE) destroy-infra

# ── Terraform shell (state surgery / escape hatch) ───────────────────────────────

## Drop into a subshell primed for a terraform root: fresh backend creds, -reconfigure
## init, cd'd into the root dir, and (bootstrap only) TF_VAR_namespace_config exported.
## Then run terraform directly with your shell's OWN quoting — no make quoting layer,
## so bracketed addresses just work:
##   terraform state list
##   terraform state rm 'module.tenant["tenant-1"].module.svns["dev-1"].vcfa_supervisor_namespace.supervisor_namespace'
## `exit` to leave. Usage: make shell ROOT=<infra|bootstrap>
shell: state-backend
	@if [ -z '$(TF_ROOT_DIR)' ]; then echo "usage: make shell ROOT=<infra|bootstrap>" >&2; exit 1; fi
	@terraform -chdir=$(TF_ROOT_DIR) init -reconfigure >/dev/null
	@cd $(TF_ROOT_DIR); \
	  if [ '$(ROOT)' = 'bootstrap' ]; then \
	    export TF_VAR_namespace_config="$$($(SRC_BACKEND) terraform -chdir=$(INFRA_DIR) output -json namespace_config 2>/dev/null)"; \
	    [ -z "$$TF_VAR_namespace_config" ] && echo "warn: infra namespace_config empty — state subcommands work; plan/apply/destroy won't" >&2; \
	  fi; \
	  echo "primed terraform shell → $(ROOT) ($(TF_ROOT_DIR)); run terraform directly, 'exit' to leave"; \
	  exec $${SHELL:-bash}
