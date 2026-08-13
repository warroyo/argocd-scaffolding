#!/usr/bin/env bash
# Print the VCFA bearer the vcf CLI already holds, to paste into Headlamp's
# cluster "token" login. It is a normal VCFA id/access token (iss=<vcfa>/oidc);
# the workload apiserver accepts it via the oidc-auth component (env-shared
# audience). The token is NOT cluster-scoped — the same one works on every
# cluster whose apiserver trusts VCFA. See docs/GETTING-STARTED.md and
# docs/ARCHITECTURE.md "VCFA identity".
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
