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
#   4. cluster names are globally unique (ArgoCD cluster registrations and the
#      cluster-apps '{{.name}}-apps' Applications are keyed by bare cluster name).
#   5. an apps/ dir that declares a `vars` cluster_name (for the apps-side
#      injector) declares the directory's cluster name.
#   6. docs/examples/cluster-template still builds (via a temp copy at the real
#      directory depth), so the template can't rot silently.
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
}

echo "building argocd"
kustomize build argocd >/dev/null || fail "kustomize build failed: argocd"

seen_clusters=""
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

  # Cluster names must be unique across ALL projects (ArgoCD registrations and
  # the cluster-apps Applications are keyed by bare cluster name).
  case " $seen_clusters " in
    *" $cluster "*) fail "$dir: cluster name '$cluster' is already used by another cluster directory — cluster names must be globally unique" ;;
  esac
  seen_clusters="$seen_clusters $cluster"

  echo "building $dir"
  build_check "$dir"
  if [ -d "$dir/apps" ]; then
    # The apps tree can't read ../cluster-details.yaml (kustomize load
    # restrictions), so a cluster using the apps-side injector re-declares
    # cluster_name — make sure the copies agree.
    apps_cluster="$(grep -o 'cluster_name=[^ ]*' "$dir/apps/kustomization.yaml" 2>/dev/null | head -1 | cut -d= -f2)"
    if [ -n "$apps_cluster" ] && [ "$apps_cluster" != "$cluster" ]; then
      fail "$dir/apps/kustomization.yaml: vars cluster_name is '$apps_cluster' but the directory implies '$cluster'"
    fi
    echo "building $dir/apps"
    build_check "$dir/apps"
  fi
done < <(find infrastructure/clusters -name cluster-details.yaml)

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
build_check "$TPL_PROJECT/tmpl-ns/tmpl-cluster"
kustomize build "$TPL_PROJECT/tmpl-ns/tmpl-cluster/apps" >/dev/null \
  || fail "kustomize build failed: docs/examples/cluster-template/apps"

if [ "$rc" -eq 0 ]; then
  echo "OK: all kustomize entrypoints build"
else
  echo "FAILED: see errors above" >&2
fi
exit $rc
