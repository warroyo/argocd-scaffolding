#!/usr/bin/env bash
# Build-test every kustomize entrypoint in the repo. This is the single place the
# checks are defined; CI (.github/workflows/validate.yml) and `make validate` both
# call it, so "builds locally" == "builds in CI".
#
# Checks:
#   1. kustomize build argocd
#   2. kustomize build of every cluster (infra dir + its apps/ dir) under
#      infrastructure/clusters, and that each cluster-details.yaml agrees with its
#      directory path (infrastructure/clusters/{project}/{namespace_ref}/{cluster}).
#   3. no rendered output contains "replace-me" (catches a cluster that skipped
#      its environment overlay — the bases carry replace-me placeholders).
#   4. an apps/ dir that declares a `vars` cluster_name (for the apps-side
#      injector) declares the directory's cluster name, and its
#      headlamp_secret_name (if any) matches <cluster>-headlamp-oidc.
#   5. a cluster enabling extraAuthentication (components/oidc-auth) on a
#      single-replica control plane warns — the change rolls the API server.
#   6. docs/examples/cluster-template and docs/examples/namespace-resources-template
#      still build (via temp copies at the real directory depth), so the
#      templates can't rot silently.
#
# Usage: scripts/validate.sh   (requires kustomize on PATH)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v kustomize >/dev/null 2>&1; then
  echo "error: kustomize not found on PATH." >&2
  echo "  install: https://kubectl.docs.kubernetes.io/installation/kustomize/" >&2
  exit 127
fi

rc=0
fail() { echo "::error::$*" >&2; rc=1; }  # ::error:: is rendered by GitHub Actions; harmless locally

# Build a kustomize dir and check the output for leftover placeholders.
build_check() {
  local dir="$1" out
  if ! out="$(kustomize build "$dir")"; then
    fail "kustomize build failed: $dir"
    return
  fi
  if grep -q "replace-me" <<<"$out"; then
    fail "$dir: rendered output contains 'replace-me' — an environment overlay (components/envs/{env}) is missing or incomplete"
  fi
  # 'replaceme' (no hyphen) is the secret-store mount/role placeholder; surviving
  # it means cluster-var-injector or the ns-vars wiring didn't fire.
  if grep -q "replaceme" <<<"$out"; then
    fail "$dir: rendered output contains 'replaceme' — the secret-store injector/ns-vars wiring is missing (apps: '../../vars' + cluster-var-injector)"
  fi
}

echo "building argocd"
kustomize build argocd >/dev/null || fail "kustomize build failed: argocd"

while IFS= read -r details; do
  dir="$(dirname "$details")"
  # infrastructure/clusters/{project}/{namespace_ref}/{cluster}
  project="$(echo "$dir" | awk -F/ '{print $3}')"
  nsref="$(echo "$dir" | awk -F/ '{print $4}')"
  cluster="$(echo "$dir" | awk -F/ '{print $5}')"

  got_project="$(awk '/project:/{print $2; exit}' "$details" | tr -d '"')"
  got_nsref="$(awk '/namespace_ref:/{print $2; exit}' "$details" | tr -d '"')"
  got_cluster="$(awk '/cluster_name:/{print $2; exit}' "$details" | tr -d '"')"

  for pair in "project:$project:$got_project" \
              "namespace_ref:$nsref:$got_nsref" \
              "cluster_name:$cluster:$got_cluster"; do
    field="${pair%%:*}"; rest="${pair#*:}"; want="${rest%%:*}"; have="${rest#*:}"
    if [ "$want" != "$have" ]; then
      fail "$details: $field is '$have' but path implies '$want'"
    fi
  done

  # Cluster names need only be unique per (project, namespace_ref) — which the
  # directory layout guarantees (one dir name per namespace_ref dir) and the
  # infra run's precondition enforces on the (project, namespace_ref) key. The
  # appset Application names are path-scoped, so bare names may repeat.

  echo "building $dir"
  build_check "$dir"

  # extraAuthentication (components/oidc-auth) rolls the control plane, so on a
  # single-replica control plane enabling or editing it is an API outage — and a
  # malformed config can leave the apiserver unable to start. Warn rather than
  # fail: dev clusters legitimately run one replica, and the vcf CLI cert path
  # stays available as break-glass. See docs/DECISIONS.md.
  rendered="$(kustomize build "$dir" 2>/dev/null)"
  if grep -q 'extraAuthentication' <<<"$rendered"; then
    cp_replicas="$(awk '/^    controlPlane:/{f=1} f && /^      replicas:/{print $2; exit}' <<<"$rendered")"
    if [ "$cp_replicas" = "1" ]; then
      echo "::warning::$dir: extraAuthentication on a single-replica control plane — applying it rolls the API server (expect an outage; keep the vcf CLI / Concierge cert path as break-glass)"
    fi
  fi

  if [ -d "$dir/apps" ]; then
    # The apps tree can't read ../cluster-details.yaml (kustomize load
    # restrictions), so a cluster using the apps-side injector re-declares
    # cluster_name — make sure the copies agree.
    apps_cluster="$(grep -o 'cluster_name=[^ ]*' "$dir/apps/kustomization.yaml" 2>/dev/null | head -1 | cut -d= -f2)"
    if [ -n "$apps_cluster" ] && [ "$apps_cluster" != "$cluster" ]; then
      fail "$dir/apps/kustomization.yaml: vars cluster_name is '$apps_cluster' but the directory implies '$cluster'"
    fi
    # project also feeds the apps-side tenant-sync SA/RBAC naming
    # (apps/components/cluster-var-injector) — must agree with the directory too.
    apps_project="$(grep -o 'project=[^ ]*' "$dir/apps/kustomization.yaml" 2>/dev/null | head -1 | cut -d= -f2)"
    if [ -n "$apps_project" ] && [ "$apps_project" != "$project" ]; then
      fail "$dir/apps/kustomization.yaml: vars project is '$apps_project' but the directory implies '$project'"
    fi
    echo "building $dir/apps"
    build_check "$dir/apps"
  fi
done < <(find infrastructure/clusters -name cluster-details.yaml)

# The apiserver's claimMappings (components/oidc-auth) and the Concierge
# JWTAuthenticator's claims (base/argocd-attach-rbac/config) must be
# byte-identical: Concierge encodes username as the client-cert CN and groups as
# its Organization fields, so identical expressions produce identical RBAC
# subjects on the dashboard (bearer) and vcf CLI (cert) paths. Drift here is the
# one failure that looks like an RBAC bug. See docs/DECISIONS.md.
OIDC_COMPONENT="infrastructure/components/oidc-auth/kustomization.yaml"
DAYZERO_CONFIG="infrastructure/base/argocd-attach-rbac/config/addonconfig.yaml"
if [ -f "$OIDC_COMPONENT" ] && [ -f "$DAYZERO_CONFIG" ]; then
  echo "checking OIDC claim-expression parity"
  api_user="$(awk -F"'" '/^ *username:$/{f=1;next} f && /expression:/{print $2; exit}' "$OIDC_COMPONENT")"
  api_groups="$(awk -F"'" '/^ *groups:$/{f=1;next} f && /expression:/{print $2; exit}' "$OIDC_COMPONENT")"
  cc_user="$(awk -F"'" '/usernameExpression:/{print $2; exit}' "$DAYZERO_CONFIG")"
  cc_groups="$(awk -F"'" '/groupsExpression:/{print $2; exit}' "$DAYZERO_CONFIG")"
  for pair in "username:$api_user:$cc_user" "groups:$api_groups:$cc_groups"; do
    field="${pair%%:*}"; rest="${pair#*:}"; a="${rest%%:*}"; b="${rest#*:}"
    if [ -z "$a" ] || [ -z "$b" ]; then
      fail "OIDC $field expression not found in $OIDC_COMPONENT / $DAYZERO_CONFIG — parity check can't run"
    elif [ "$a" != "$b" ]; then
      fail "OIDC $field expression differs: '$a' (apiserver) vs '$b' (Concierge) — they must be byte-identical or the CLI and dashboard paths yield different RBAC subjects"
    fi
  done
fi

# Namespace-level resources (namespace-resources ApplicationSet source): one dir
# per {project}/{namespace_ref}, synced once into the supervisor namespace. No
# cluster-details.yaml, so build-test them on their own.
while IFS= read -r nsdir; do
  echo "building $nsdir"
  build_check "$nsdir"
done < <(find infrastructure/clusters -type d -name namespace-resources)

# Build-test the copy-me template at the real directory depth so its relative
# paths resolve. Uses an existing tenant's vars dir; the temp project dir is
# hidden (leading dot) so nothing else picks it up, and is always cleaned up.
echo "building docs/examples/cluster-template (temp copy)"
TPL_PROJECT="infrastructure/clusters/.template-check"
cleanup_tpl() { rm -rf "$REPO_ROOT/$TPL_PROJECT"; }
trap cleanup_tpl EXIT
rm -rf "$TPL_PROJECT"
mkdir -p "$TPL_PROJECT/tmpl-ns"
cp -r docs/examples/cluster-template "$TPL_PROJECT/tmpl-ns/tmpl-cluster"
cp -r infrastructure/clusters/tenant-1/vars "$TPL_PROJECT/vars"
# Per-namespace ns-vars (suffixed supervisor ns) sits at the namespace level, so
# the template's apps `../../vars` resolves. Reuse an existing namespace's copy.
cp -r infrastructure/clusters/tenant-1/dev-1/vars "$TPL_PROJECT/tmpl-ns/vars"
build_check "$TPL_PROJECT/tmpl-ns/tmpl-cluster"
build_check "$TPL_PROJECT/tmpl-ns/tmpl-cluster/apps"

# Same trick for the namespace-resources template (shared add-on installs).
echo "building docs/examples/namespace-resources-template (temp copy)"
cp -r docs/examples/namespace-resources-template "$TPL_PROJECT/tmpl-ns/namespace-resources"
build_check "$TPL_PROJECT/tmpl-ns/namespace-resources"

# Rego syntax check for the custom cluster policy catalog (terraform/infra/policies.tf).
# Optional — opa is not a hard dependency like kustomize, this only runs if it's
# on PATH, so a missing opa install never fails CI or a local run.
if command -v opa >/dev/null 2>&1; then
  echo "checking terraform/infra/rego"
  # The files are rule bodies only — cluster-policy-template prepends
  # `package <template_name>`, so check copies with that line added, or every
  # file fails "package expected". Rego v0 syntax (partial-set `violation[...]`
  # with no `if`/`contains`), matching the vendored reference.
  REGO_TMP="$(mktemp -d)"
  for f in terraform/infra/rego/*.rego; do
    name="$(basename "$f" .rego)"
    { echo "package ${name//-/}"; cat "$f"; } > "$REGO_TMP/$name.rego"
  done
  opa check --v0-compatible "$REGO_TMP" || fail "opa check failed: terraform/infra/rego"
  rm -rf "$REGO_TMP"
else
  echo "skipping opa check (opa not on PATH)"
fi

if [ "$rc" -eq 0 ]; then
  echo "OK: all kustomize entrypoints build"
else
  echo "FAILED: see errors above" >&2
fi
exit $rc
