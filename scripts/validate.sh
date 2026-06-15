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

  echo "building $dir"
  kustomize build "$dir" >/dev/null || fail "kustomize build failed: $dir"
  if [ -d "$dir/apps" ]; then
    kustomize build "$dir/apps" >/dev/null || fail "kustomize build failed: $dir/apps"
  fi
done < <(find infrastructure/clusters -name cluster-details.yaml)

if [ "$rc" -eq 0 ]; then
  echo "OK: all kustomize entrypoints build"
else
  echo "FAILED: see errors above" >&2
fi
exit $rc
