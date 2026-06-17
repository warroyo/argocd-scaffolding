# Auto-sourced by every Makefile recipe via BASH_ENV. Loads the repo .env with normal
# shell parsing (quotes, spaces and # comments handled natively) and exports the vars so
# terraform picks up TF_VAR_*. No-op when .env is absent. Not meant to be run directly.
set -a
[ -n "${ENV_FILE:-}" ] && [ -f "$ENV_FILE" ] && . "$ENV_FILE"
set +a
