# Claude Instructions for argocd-scaffolding

## README hygiene

After **any** change to the following, update `README.md` to stay in sync —
and keep `docs/ARCHITECTURE.md` (including its mermaid diagrams and the
pattern-vs-lab seams table), `docs/DECISIONS.md`, and `docs/GETTING-STARTED.md`
(its commands, file paths, and expected-output blocks) accurate when the flow,
contracts, or design decisions they describe change:
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
| `infrastructure/clusters/*/vars/tenant-vars.yaml` | `terraform/infra` → `templates/tenant-vars.yaml.tftpl` (needs state: `argo_namespace`) |
| `infrastructure/clusters/*/vars/kustomization.yaml` | `terraform/infra` → `templates/vars-kustomization.yaml.tftpl` |
| `terraform/bootstrap/providers.tf` | `terraform/infra` → `templates/bootstrap-providers.tf.tftpl` |
| `terraform/bootstrap/main.tf` | `terraform/infra` → `templates/bootstrap-main.tf.tftpl` |
| `.kube-backend.config` | `terraform/state-backend` → `local_sensitive_file` in `generate.tf` (kubeconfig with host + token for the kubernetes backend; each root's `backend.tf` sets `config_path` to it; holds a token; **gitignored**, never commit) |
| `.kube-backend.env` | `terraform/state-backend` → `local_sensitive_file` in `generate.tf` (`KUBE_NAMESPACE` — the one backend setting not read from the kubeconfig; sourced by the Makefile; **gitignored**, never commit) |

Note: the `infra`-type tenant's AppProject is always rendered as
`argocd/projects/infra.yaml` (named `infra` — the project the ApplicationSets
target), regardless of the tenant's name. There is no separate hand-authored
`infra` AppProject.

## Source of truth files — edit these, not the generated output

| File | Controls |
|------|---------|
| `terraform/infra/tenants.yaml` | Tenants, namespaces (incl. `environment`), ArgoCD bootstrap, cluster labels, optional `source_repos` (tenant AppProject scoping) and `vpc_private_cidr` |
| `infrastructure/profiles/{env}/`, `apps/profiles/{env}/` | The inherited default set per environment (bases + always-on components + env overlay). Edit to change every cluster in an environment at once. |
| `infrastructure/components/envs/{env}/`, `apps/components/envs/{env}/` | Real per-environment values AND version pins (bases hold only `replace-me` placeholders). Always-on versions (cluster class, k8s, AKO; package bundle/baseline) apply via the profiles; optional-feature versions live in feature-scoped sub-components (`envs/{env}/istio`, `envs/{env}/observability`) that clusters include alongside the feature. Per-cluster canary: `patches:` in the cluster kustomization. |
| `infrastructure/clusters/{project}/{namespace_ref}/{cluster}/` | Hand-authored cluster: `kustomization.yaml` (references a profile + deltas + override patches), `apps/kustomization.yaml`, `cluster-details.yaml` |
| `terraform/bootstrap/locals.tf` | Merges secrets (argo_password) into the per-namespace config from the infra run's `namespace_config` output; repo_url defaults from `argocd/repo-config.yaml`. The `gitops.platform/*` label taxonomy and suffixed namespace names are computed in `terraform/infra/main.tf`. Per-namespace helm tokens are minted fresh by `terraform/bootstrap/vcfa.tf` (no kubeconfigs shuttle). |
| `argocd/repo-config.yaml` | Single repo URL used by all ApplicationSets |
| `docs/examples/cluster-template/` | Copy-me template for a new cluster |
| `terraform/state-namespace/{project,state-namespace}.yaml` | CCI `Project` + `SupervisorNamespace` CRs for the Terraform-state backend. Applied once out-of-band with `kubectl` (README → Backend Configuration explains the design; the commands live in `docs/GETTING-STARTED.md` Part 1). |
| `terraform/state-backend/namespace.auto.tfvars` | The captured (generated) state-namespace name fed to the stateless `terraform/state-backend` helper. Non-secret; committed. |

## Decision model (label-based targeting)

Each supervisor namespace registers to ArgoCD with `clusterLabels`
(`type: supervisor-ns`, `gitops.platform/project`, `gitops.platform/namespace-ref`,
`gitops.platform/environment`, and `gitops.platform/namespace` = the vcfa-suffixed
name captured at install). The `cluster-provisioning` ApplicationSet joins a cluster
directory to its supervisor namespace on `(project, namespace_ref)` — which is also
the directory path `infrastructure/clusters/{project}/{namespace_ref}/{cluster}/`.
`namespace_ref` must be unique per project (enforced by a precondition in
`terraform/infra/generate.tf`).

The workload `ArgoCluster` registrations mirror this taxonomy (`type: tenant` as
the coarse selector, plus `gitops.platform/project` and
`gitops.platform/namespace-ref` injected by `cluster-var-injector`). The
`cluster-apps` ApplicationSet uses both join keys, so its git path is exact —
`infrastructure/clusters/{project}/{namespace_ref}/{cluster}/` — not a wildcard.

## Local testing

Run `make validate` (or `./scripts/validate.sh`) before pushing — it build-tests every
kustomize entrypoint (argocd root + each cluster's infra and `apps/` dirs + a temp copy of
`docs/examples/cluster-template`), checks each `cluster-details.yaml` against its directory
path, rejects `replace-me` in rendered output (a cluster missing its env overlay), enforces
globally-unique cluster names, and cross-checks the apps-side `vars` cluster_name. CI runs
the same script, plus `terraform fmt -check` / `terraform validate` in `validate.yml`.
Requires `kustomize`.

## Workflows

### Adding a new tenant
1. Add an entry to `terraform/infra/tenants.yaml` (set per-namespace `environment`).
2. Run `make apply` (or push to `main` — the Apply workflow runs it; it triggers on
   `terraform/**` and `charts/bootstrap-tenant/**`). `apply-infra` provisions the
   namespaces and renders the AppProject, tenant-vars, and bootstrap wiring; commit
   those, then bootstrap runs (`apply-bootstrap` refuses while rendered files are
   uncommitted — `SKIP_GENERATED_CHECK=1` overrides).

### Adding a new cluster
1. `cp -r docs/examples/cluster-template infrastructure/clusters/{project}/{namespace_ref}/{cluster}`
2. Edit `cluster-details.yaml` (`cluster_name`, `project`, `namespace_ref` — must match
   the directory path; `validate.yml` enforces this).
3. In `kustomization.yaml` / `apps/kustomization.yaml`, reference the environment
   profile (`profiles/{env}`) and add only the optional feature components / app
   stacks and any override patches. Pair every optional feature with its
   `envs/{env}` sub-component (istio → `envs/{env}/istio`; observability →
   `apps/components/envs/{env}/observability`) — it pins the feature's version;
   forgetting it leaves `replace-me` in rendered output and fails `make validate`.
   Keep `cluster-var-injector` **last** in the infra
   component list (it rewrites resources brought in by the profile and the components).
   If the cluster uses `apps/base/istio-ako-patch`, also enable the apps-side injector
   (`apps/components/cluster-var-injector`, last) and the `vars` configMapGenerator
   with this cluster's `cluster_name` (the apps tree can't read
   `../cluster-details.yaml` — kustomize load restrictions).
4. Commit. The `cluster-provisioning` ApplicationSet picks it up via label join — the
   vcfa-generated namespace name is resolved from the cluster registration, not git.

### Changing every cluster in an environment
Edit `infrastructure/profiles/{env}` (or `apps/profiles/{env}`) — every cluster that
references that profile inherits the change. Real per-environment values live in
`infrastructure/components/envs/{env}`.

### Rolling a version
Versions are never pinned in bases. Bump the pin in the env layer —
`infrastructure/components/envs/{env}` (cluster class, k8s, AKO),
`envs/{env}/istio`, `apps/components/envs/{env}` (package bundle, cert-manager),
or `apps/components/envs/{env}/observability` — dev first, then prod. Canary a
single cluster with a `patches:` override in its kustomization before bumping the
env pin.
