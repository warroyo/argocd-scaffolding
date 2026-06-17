# Auto-sourced by every Makefile recipe via BASH_ENV. Loads, with normal shell parsing:
#   - $ENV_FILE      (.env)              — user-edited TF_VAR_* (vcfa creds, secrets)
#   - $BACKEND_ENV   (.kube-backend.env) — generated KUBE_* for the kubernetes backend
# and exports them so terraform picks them up. No-op when a file is absent. Not run directly.
set -a
[ -n "${ENV_FILE:-}" ]    && [ -f "$ENV_FILE" ]    && . "$ENV_FILE"
[ -n "${BACKEND_ENV:-}" ] && [ -f "$BACKEND_ENV" ] && . "$BACKEND_ENV"
set +a
