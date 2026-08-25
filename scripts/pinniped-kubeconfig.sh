#!/usr/bin/env bash
# Generate a Pinniped (Concierge) kubeconfig for a workload cluster from inside a
# VCFA namespace context. Replaces `vcf cluster kubeconfig get`, which a tenant
# can never run: it polls the CAPI admin kubeconfig Secret and a tenant's 403 is
# treated as "not ready yet", so it hangs forever. See docs/GETTING-STARTED.md.
#
# Everything is derived from the current CCI context — nothing is hardcoded:
#   server / concierge endpoint  Cluster.spec.controlPlaneEndpoint
#   workload cluster uuid        Cluster.metadata.uid
#   VCFA endpoint                scheme+host of the context's server URL
#   VCFA CA                      the context's certificate-authority-data
#   tenant name                  `org_name` claim of the context's token
# The guest cluster CA is the one value VCFA does not expose to a tenant — see
# --ca-file / --insecure below.
#
# Usage: scripts/pinniped-kubeconfig.sh CLUSTER [options]
set -euo pipefail

CLUSTER=""; NAMESPACE=""; KCONTEXT=""; OUT=""; CA_FILE=""; INSECURE=0; CTX_NAME=""

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") CLUSTER [-n NAMESPACE] [--context CCI_CONTEXT]
                        [-o OUTPUT] [--ca-file FILE] [--insecure] [--name CONTEXT_NAME]

  -n, --namespace    supervisor namespace (default: the context's namespace)
      --context      CCI context to read from (default: current context)
  -o, --output       write kubeconfig here (default: stdout)
      --ca-file      PEM file holding the guest cluster CA. Only needed when the
                     CA cannot be discovered — see below.
      --insecure     emit insecure-skip-tls-verify instead of a CA. Last resort.
      --name         name for the generated cluster/user/context

The guest CA is looked for in this order: the Pinniped CredentialIssuer (needs
RBAC a tenant usually lacks), then any local kubeconfig entry already pointing at
the same server, then --ca-file. A tenant with none of those needs the platform
to hand over the CA once — it is a public certificate, safe to share.
EOF
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--namespace) NAMESPACE="$2"; shift 2 ;;
    --context)      KCONTEXT="$2"; shift 2 ;;
    -o|--output)    OUT="$2"; shift 2 ;;
    --ca-file)      CA_FILE="$2"; shift 2 ;;
    --insecure)     INSECURE=1; shift ;;
    --name)         CTX_NAME="$2"; shift 2 ;;
    -h|--help)      usage ;;
    -*)             echo "unknown flag: $1" >&2; usage ;;
    *)              [ -z "$CLUSTER" ] || usage; CLUSTER="$1"; shift ;;
  esac
done
[ -n "$CLUSTER" ] || usage

for bin in kubectl jq; do
  command -v "$bin" >/dev/null || { echo "error: $bin not found on PATH" >&2; exit 1; }
done

KCONTEXT="${KCONTEXT:-$(kubectl config current-context)}"
KUBECTL=(kubectl --context="$KCONTEXT")
[ -n "$NAMESPACE" ] && KUBECTL+=(--namespace="$NAMESPACE")

# ── Values read straight off the CCI context ──────────────────────────────────
CFG="$(kubectl config view --raw -o json)"
ctx_cluster="$(jq -r --arg c "$KCONTEXT" '.contexts[]|select(.name==$c)|.context.cluster' <<<"$CFG")"
ctx_user="$(jq -r --arg c "$KCONTEXT" '.contexts[]|select(.name==$c)|.context.user' <<<"$CFG")"
[ -n "$ctx_cluster" ] && [ "$ctx_cluster" != "null" ] || { echo "error: context '$KCONTEXT' not found" >&2; exit 1; }

cci_server="$(jq -r --arg n "$ctx_cluster" '.clusters[]|select(.name==$n)|.cluster.server' <<<"$CFG")"
vcfa_ca="$(jq -r --arg n "$ctx_cluster" '.clusters[]|select(.name==$n)|.cluster."certificate-authority-data" // ""' <<<"$CFG")"
# https://host/proxy/k8s/namespaces/... -> https://host
vcfa_endpoint="$(sed -E 's#^(https?://[^/]+).*#\1#' <<<"$cci_server")"
[ -n "$vcfa_ca" ] || { echo "error: context '$KCONTEXT' carries no certificate-authority-data" >&2; exit 1; }

# Tenant (org) name comes from the token's own claims, not from CLI config.
token="$(jq -r --arg u "$ctx_user" '.users[]|select(.name==$u)|.user.token // ""' <<<"$CFG")"
claim() {
  [ -n "$token" ] || return 1
  local payload="${token#*.}"; payload="${payload%%.*}"
  local pad=$(( (4 - ${#payload} % 4) % 4 ))
  local b64 json
  b64="$(printf '%s%s' "$payload" "$(printf '=%.0s' $(seq 1 "$pad" 2>/dev/null))" | tr '_-' '/+')"
  # base64 exits non-zero on trailing bytes it still decodes — don't let that
  # (under pipefail) look like a missing claim.
  json="$(printf '%s' "$b64" | base64 -d 2>/dev/null || true)"
  [ -n "$json" ] || return 1
  jq -er --arg k "$1" '.[$k] // empty' <<<"$json"
}
tenant="$(claim org_name || true)"
[ -n "$tenant" ] || { echo "error: no org_name claim on the context token — log in to VCFA first" >&2; exit 1; }
whoami_claim="$(claim preferred_username || echo "$ctx_user")"

# ── Values read from the cluster object ───────────────────────────────────────
cluster_json="$("${KUBECTL[@]}" get cluster.cluster.x-k8s.io "$CLUSTER" -o json)"
uid="$(jq -r '.metadata.uid' <<<"$cluster_json")"
host="$(jq -r '.spec.controlPlaneEndpoint.host' <<<"$cluster_json")"
port="$(jq -r '.spec.controlPlaneEndpoint.port' <<<"$cluster_json")"
[ -n "$host" ] && [ "$host" != "null" ] || { echo "error: $CLUSTER has no controlPlaneEndpoint yet" >&2; exit 1; }
server="https://${host}:${port}"
ns="$(jq -r '.metadata.namespace' <<<"$cluster_json")"

# ── Guest cluster CA: the one value VCFA does not hand a tenant ───────────────
guest_ca=""
if [ -n "$CA_FILE" ]; then
  guest_ca="$(base64 -w0 < "$CA_FILE")"
elif ca="$("${KUBECTL[@]}" get credentialissuers.config.concierge.pinniped.dev -o json 2>/dev/null \
            | jq -r '[.items[].status.strategies[]?|select(.status=="Success")
                      |.frontend.tokenCredentialRequestInfo.certificateAuthorityData//empty][0]//empty')" \
     && [ -n "$ca" ]; then
  guest_ca="$ca"   # Pinniped publishes it here for anyone with RBAC to read it
elif ca="$(jq -r --arg s "$server" '[.clusters[]|select(.cluster.server==$s)
             |.cluster."certificate-authority-data"//empty][0]//empty' <<<"$CFG")" && [ -n "$ca" ]; then
  guest_ca="$ca"   # already trusted locally for this exact server
elif [ "$INSECURE" -eq 0 ]; then
  echo "error: could not discover the CA for $server." >&2
  echo "  Pass --ca-file with the guest cluster CA (a public cert), or --insecure." >&2
  exit 1
fi

# ── Emit ──────────────────────────────────────────────────────────────────────
name="${CTX_NAME:-${CLUSTER}-${ns}}"
# The credential cache is keyed by cluster UUID only, so two identities sharing
# the default file evict each other. Scope it per user.
cache="${HOME}/.config/vcf/vcfa/credentials-$(tr -c 'A-Za-z0-9_.-' '_' <<<"$whoami_claim").json"

if [ -n "$guest_ca" ]; then
  tls="    certificate-authority-data: ${guest_ca}"
else
  tls="    insecure-skip-tls-verify: true"
fi

render() {
  cat <<EOF
apiVersion: v1
kind: Config
current-context: ${name}
clusters:
- name: ${name}
  cluster:
    server: ${server}
${tls}
contexts:
- name: ${name}
  context:
    cluster: ${name}
    user: ${name}
users:
- name: ${name}
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: vcf
      interactiveMode: IfAvailable
      args:
      - vcfa-auth
      - login
      - --concierge-endpoint=${server}
      - --concierge-ca-bundle-data=${guest_ca}
      - --vcfaEndpoint=${vcfa_endpoint}
      - --vcfa-ca-certificate=${vcfa_ca}
      - --vcfa-tenant-name=${tenant}
      - --workload-cluster-name=${CLUSTER}
      - --workload-cluster-uuid=${uid}
      - --credential-cache=${cache}
EOF
}

if [ -n "$OUT" ]; then
  render > "$OUT"
  echo "wrote $OUT (context '${name}', identity ${whoami_claim})" >&2
  echo "  KUBECONFIG=$OUT kubectl auth whoami" >&2
else
  render
fi
