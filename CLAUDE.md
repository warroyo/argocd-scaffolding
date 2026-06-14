# Claude Instructions for argocd-scaffolding

## README hygiene

After **any** change to the following, update `README.md` to stay in sync:
- Directory structure (new dirs, renamed dirs, removed dirs)
- Key technologies (added/removed tools or frameworks)
- Workflow steps (new tenant, new cluster, deploying apps)
- Terraform layout, modules, or the `terraform/infra/templates/` generators
- GitHub Actions workflows (`.github/workflows/`) — triggers and behavior
- The cluster directory layout and label/decision model

Do not leave `README.md` describing a state that no longer exists in the repo.

## Generated files — do not edit manually

All generation now happens inside the **infra Terraform run** (`local_file` +
`templatefile`, see `terraform/infra/generate.tf` and `terraform/infra/templates/`).
There is no Python generator and no ytt. These files are produced/refreshed by
`make apply-infra` and must not be edited by hand:

| File | Rendered by (template) |
|------|------------------------|
| `argocd/projects/*.yaml` | `terraform/infra` → `templates/appproject.yaml.tftpl` |
| `argocd/projects/kustomization.yaml` | `terraform/infra` → `templates/projects-kustomization.yaml.tftpl` |
| `infrastructure/clusters/*/vars/tenant-vars.yaml` | `terraform/infra` → `templates/tenant-vars.yaml.tftpl` (needs state: `tenant_uuid`, `argo_namespace`) |
| `infrastructure/clusters/*/vars/kustomization.yaml` | `terraform/infra` → `templates/vars-kustomization.yaml.tftpl` |
| `terraform/bootstrap/providers.tf` | `terraform/infra` → `templates/bootstrap-providers.tf.tftpl` |
| `terraform/bootstrap/main.tf` | `terraform/infra` → `templates/bootstrap-main.tf.tftpl` |

Note: `argocd/projects/infra.yaml` (the static `infra` AppProject used by the
ApplicationSets) is hand-authored and intentionally not in the generated
kustomization.

## Source of truth files — edit these, not the generated output

| File | Controls |
|------|---------|
| `terraform/infra/tenants.yaml` | Tenants, namespaces (incl. `environment`), ArgoCD bootstrap, cluster labels |
| `infrastructure/profiles/{env}/`, `apps/profiles/{env}/` | The inherited default set per environment (bases + always-on components + env overlay). Edit to change every cluster in an environment at once. |
| `infrastructure/components/envs/{env}/` | Real per-environment values (bases hold only `replace-me` placeholders) |
| `infrastructure/clusters/{project}/{namespace_ref}/{cluster}/` | Hand-authored cluster: `kustomization.yaml` (references a profile + deltas + override patches), `apps/kustomization.yaml`, `cluster-details.yaml` |
| `terraform/bootstrap/locals.tf` | Per-namespace bootstrap config + the `gitops.platform/*` label taxonomy |
| `argocd/repo-config.yaml` | Single repo URL used by all ApplicationSets |
| `docs/examples/cluster-template/` | Copy-me template for a new cluster |

## Decision model (label-based targeting)

Each supervisor namespace registers to ArgoCD with `clusterLabels`
(`type: supervisor-ns`, `gitops.platform/project`, `gitops.platform/namespace-ref`,
`gitops.platform/environment`, and `gitops.platform/namespace` = the vcfa-suffixed
name captured at install). The `cluster-provisioning` ApplicationSet joins a cluster
directory to its supervisor namespace on `(project, namespace_ref)` — which is also
the directory path `infrastructure/clusters/{project}/{namespace_ref}/{cluster}/`.
`namespace_ref` must be unique per project (enforced by a precondition in
`terraform/infra/generate.tf`).

## Workflows

### Adding a new tenant
1. Add an entry to `terraform/infra/tenants.yaml` (set per-namespace `environment`).
2. Run `make apply` (or push to `main` — the Apply workflow runs it). `apply-infra`
   provisions the namespaces and renders the AppProject, tenant-vars, and bootstrap
   wiring; commit those, then bootstrap runs.

### Adding a new cluster
1. `cp -r docs/examples/cluster-template infrastructure/clusters/{project}/{namespace_ref}/{cluster}`
2. Edit `cluster-details.yaml` (`cluster_name`, `project`, `namespace_ref` — must match
   the directory path; `validate.yml` enforces this).
3. In `kustomization.yaml` / `apps/kustomization.yaml`, reference the environment
   profile (`profiles/{env}`) and add only the optional feature components / app
   stacks and any override patches. Keep `cluster-var-injector` **last** in the infra
   component list (it rewrites resources brought in by the profile and the components).
4. Commit. The `cluster-provisioning` ApplicationSet picks it up via label join — the
   vcfa-generated namespace name is resolved from the cluster registration, not git.

### Changing every cluster in an environment
Edit `infrastructure/profiles/{env}` (or `apps/profiles/{env}`) — every cluster that
references that profile inherits the change. Real per-environment values live in
`infrastructure/components/envs/{env}`.
