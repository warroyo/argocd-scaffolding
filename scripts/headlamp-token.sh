#!/usr/bin/env bash
# Print the VCFA bearer the vcf CLI holds, to paste into Headlamp's token login.
# Accepted by any cluster with components/oidc-auth; docs/ARCHITECTURE.md "VCFA identity".
set -euo pipefail

# Renew from the stored refresh token if the CLI supports it (no-op otherwise).
vcf context refresh </dev/null >/dev/null 2>&1 || true  # </dev/null: never block on its token prompt

# The VCFA context user in the kubeconfig carries the bearer.
token="$(kubectl config view --raw -o json \
  | jq -r '.users[] | select(.name | test("^vcfa:.*@")) | .user.token' \
  | grep -v '^null$' | head -1)"

if [ -z "${token:-}" ]; then
  echo "no VCFA bearer found — log in with the vcf CLI first (vcf context create/use)" >&2
  exit 1
fi
# `vcf context refresh` can fail silently above; don't hand out a dead token.
payload="$(cut -d. -f2 <<<"$token" | tr '_-' '/+')"
while [ $(( ${#payload} % 4 )) -ne 0 ]; do payload="$payload="; done
exp="$(base64 -d <<<"$payload" 2>/dev/null | jq -r '.exp // 0' 2>/dev/null)" || exp=0
if ! [ "${exp:-0}" -gt "$(date +%s)" ] 2>/dev/null; then
  echo "cached VCFA bearer is expired — re-login (vcf context refresh, with VCF_CLI_VCFA_API_TOKEN set)" >&2
  exit 1
fi
printf '%s\n' "$token"
