#!/usr/bin/env bash
# Print the VCFA bearer the vcf CLI holds, to paste into Headlamp's token login.
# Accepted by any cluster with components/oidc-auth; docs/ARCHITECTURE.md "VCFA identity".
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
