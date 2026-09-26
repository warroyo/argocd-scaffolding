#!/usr/bin/env bash
# Assign the "ArgoCD Instance" org role to an ArgoCD instance's VCFA service
# account — the step the VCFA UI does after create and the API path skips.
# Run by terraform/bootstrap (argocd-sa-role.tf). See docs/DECISIONS.md #25.
#
# Env: KUBE_HOST KUBE_TOKEN KUBE_INSECURE NAMESPACE ARGOCD_NAME
#      VCFA_URL VCFA_ORG VCFA_REFRESH_TOKEN [ROLE_NAME] [TIMEOUT_SECONDS]
set -euo pipefail

ROLE_NAME=${ROLE_NAME:-ArgoCD Instance}
TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-600}
VCFA_URL=${VCFA_URL%/}
API_VERSION="Accept: application/json;version=40.0"
k_tls=(); [ "${KUBE_INSECURE:-false}" = true ] && k_tls=(-k)

# 1. Wait for the operator to publish the service account on the ArgoCD CR.
cr="$KUBE_HOST/apis/argocd-service.vsphere.vmware.com/v1alpha1/namespaces/$NAMESPACE/argocds/$ARGOCD_NAME"
deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
sa_id=""
while [ -z "$sa_id" ]; do
  sa_id=$(curl -sf "${k_tls[@]}" -H "Authorization: Bearer $KUBE_TOKEN" "$cr" \
    | jq -r '.status.serviceAccounts.platform.id // empty' || true)
  [ -n "$sa_id" ] && break
  [ "$(date +%s)" -ge "$deadline" ] && { echo "timed out waiting for $NAMESPACE/$ARGOCD_NAME status.serviceAccounts.platform.id" >&2; exit 1; }
  sleep 10
done

# 2. Org-admin session from the same refresh token Terraform uses.
tok=$(curl -sfk -X POST "$VCFA_URL/oauth/tenant/$VCFA_ORG/token" \
  --data-urlencode grant_type=refresh_token --data-urlencode "refresh_token=$VCFA_REFRESH_TOKEN" | jq -r .access_token)
auth="Authorization: Bearer $tok"

role=$(curl -sfk -H "$auth" -H "$API_VERSION" -G "$VCFA_URL/cloudapi/1.0.0/roles" \
  --data-urlencode "filter=name==$ROLE_NAME" | jq -c '.values[0] | {name, id}')
[ "$role" = "null" ] && { echo "role '$ROLE_NAME' not found in org $VCFA_ORG" >&2; exit 1; }

# 3. GET the service account; PUT it back with the role added (idempotent).
sa_url="$VCFA_URL/cloudapi/1.0.0/serviceAccounts/$sa_id"
sa=$(curl -sfk -H "$auth" -H "$API_VERSION" "$sa_url")
if jq -e --argjson r "$role" 'any(.roles[]?; .id == $r.id)' <<<"$sa" >/dev/null; then
  echo "$sa_id already has role '$ROLE_NAME'"
  exit 0
fi
jq --argjson r "$role" '.roles = ((.roles // []) + [$r])' <<<"$sa" \
  | curl -sfk -X PUT -H "$auth" -H "$API_VERSION" -H "Content-Type: application/json" --data-binary @- "$sa_url" >/dev/null
echo "granted '$ROLE_NAME' to $sa_id ($NAMESPACE/$ARGOCD_NAME)"
