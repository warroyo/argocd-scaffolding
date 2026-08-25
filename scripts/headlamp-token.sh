#!/usr/bin/env bash
# Print the VCFA bearer the vcf CLI already holds. It is a normal VCFA
# id/access token (iss=<vcfa>/oidc), not cluster-scoped. Workload apiservers do
# NOT accept it today — components/oidc-auth is parked (docs/BACKLOG.md), so
# this is a debugging aid (`auth whoami` against VCFA), not a cluster login.
set -euo pipefail

# Renew from the stored refresh token if the CLI supports it (no-op otherwise).
vcf context refresh >/dev/null 2>&1 || true

# The VCFA context user in the kubeconfig carries the bearer.
token="$(kubectl config view --raw -o json \
  | jq -r '.users[] | select(.name | test("^vcfa:.*@")) | .user.token' \
  | grep -v '^null$' | head -1)"

if [ -z "${token:-}" ]; then
  echo "no VCFA bearer found — log in with the vcf CLI first (vcf context create/use)" >&2
  exit 1
fi
printf '%s\n' "$token"
