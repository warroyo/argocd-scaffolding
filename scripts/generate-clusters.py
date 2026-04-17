#!/usr/bin/env python3
"""Generate cluster kustomization files from ytt templates.
Run via: make generate
Preserves namespace/argo_namespace in cluster-details.yaml across regenerations.
"""

import os, subprocess, sys, yaml

REPO_ROOT    = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLUSTERS_DIR = os.path.join(REPO_ROOT, "infrastructure", "clusters")
CLUSTER_TMPL = os.path.join(REPO_ROOT, "templates", "cluster")


def run_ytt(values_file, output_dir):
    result = subprocess.run(
        ["ytt", "-f", CLUSTER_TMPL, "-f", values_file, "--output-files", output_dir],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"ERROR: ytt failed for {values_file}:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)


def main():
    count = 0
    for root, dirs, files in os.walk(CLUSTERS_DIR):
        if "cluster-values.yaml" not in files:
            continue

        values_file  = os.path.join(root, "cluster-values.yaml")
        details_path = os.path.join(root, "cluster-details.yaml")

        # Save runtime-populated namespace fields before ytt overwrites cluster-details.yaml
        saved_ns = saved_argo_ns = ""
        if os.path.exists(details_path):
            data = (yaml.safe_load(open(details_path)) or {}).get("data") or {}
            saved_ns      = data.get("namespace", "")
            saved_argo_ns = data.get("argo_namespace", "")

        run_ytt(values_file, root)
        print(f"  ytt -> {os.path.relpath(root, REPO_ROOT)}")

        # Restore namespace fields if they were already populated by generate-details
        if saved_ns or saved_argo_ns:
            details = yaml.safe_load(open(details_path))
            details["data"]["namespace"]      = saved_ns
            details["data"]["argo_namespace"] = saved_argo_ns
            with open(details_path, "w") as f:
                f.write(yaml.dump(details, default_flow_style=False, sort_keys=False))

        count += 1

    print(f"\n{count} cluster(s) generated.")


if __name__ == "__main__":
    main()
