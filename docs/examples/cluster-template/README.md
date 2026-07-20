# Cluster template

Copy this directory to create a new cluster:

```sh
cp -r docs/examples/cluster-template \
  infrastructure/clusters/<project>/<namespace_ref>/<cluster_name>
```

Then:

1. Edit `cluster-details.yaml` — set `cluster_name` (= the directory name),
   `project` (= the `<project>` dir / tenant name), and `namespace_ref`
   (= the `<namespace_ref>` dir / the namespace `name` in
   `terraform/infra/tenants.yaml`). These three must match the directory path.
2. Edit `kustomization.yaml` — include only the components you want. Reuse comes
   from the shared `infrastructure/components/` and `infrastructure/base/`; there
   is no generation step, so you have full control. Add-ons (istio, headlamp) are
   enabled by cluster label; the shared `AddonInstall`s and their version pins
   live in the namespace's `namespace-resources/` dir — if this cluster's
   namespace doesn't have one yet, copy
   `docs/examples/namespace-resources-template` alongside this cluster dir.
3. Edit `apps/kustomization.yaml` — pick the app stacks for this cluster.
4. Commit. The `cluster-provisioning` ApplicationSet joins this directory to its
   supervisor namespace by label (`gitops.platform/project` +
   `gitops.platform/namespace-ref`) and provisions it — the vcfa-generated
   namespace name is resolved from the cluster registration, not from git.

> The relative paths below are written for the destination depth
> `infrastructure/clusters/{project}/{namespace_ref}/{cluster}/`. Validate after
> copying with `kubectl kustomize infrastructure/clusters/<project>/<namespace_ref>/<cluster_name>`.
>
> `namespace_ref` must be unique within a project (the deployment target join key).
