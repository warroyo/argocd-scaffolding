# Auto-sourced by every Makefile recipe via BASH_ENV. Loads, with normal shell parsing:
#   - $ENV_FILE (.env) — user-edited TF_VAR_* (vcfa creds, secrets)
# and exports them so terraform picks them up. No-op when the file is absent. Not run directly.
# The Kubernetes backend creds are not sourced here: the Makefile exports KUBECONFIG pointing
# at the generated .kube-backend.config kubeconfig instead.
set -a
[ -n "${ENV_FILE:-}" ] && [ -f "$ENV_FILE" ] && . "$ENV_FILE"
set +a
