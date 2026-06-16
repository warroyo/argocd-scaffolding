# ArgoCD Scaffolding Project

This repository contains the infrastructure and application configuration for managing a multi-tenant Kubernetes environment using ArgoCD, Terraform, and Kustomize.

## Getting Started

### Prerequisites

| Tool | Purpose |
|------|---------|
| `terraform` >= 1.0 | Provisions namespaces, renders generated files, bootstraps ArgoCD |
| `kustomize` | Local validation (`make validate`) — same version CI uses |
| `make` | Orchestrates the two-phase Terraform workflow |
| VCF Automation access | `vcfa_url`, `vcfa_org`, and an API refresh token |

### Required Variables

Set these **before** running `make apply`. All sensitive values go via `TF_VAR_*` exports; non-sensitive values can go in `terraform/infra/terraform.tfvars` (gitignored).

**Required for `apply-infra`:**

| Variable | How to set | Description |
|----------|-----------|-------------|
| `vcfa_refresh_token` | `export TF_VAR_vcfa_refresh_token=...` | VCF Automation API token (sensitive) |
| `vcfa_url` | tfvars or `export TF_VAR_vcfa_url=...` | VCF Automation URL (e.g. `https://vcfa.example.com`) |
| `vcfa_org` | tfvars or `export TF_VAR_vcfa_org=...` | VCF Automation org name |
| `region_name` | tfvars or `export TF_VAR_region_name=...` | Region used to name VPCs (`{tenant}-{region}-vpc`) |
| `avi_enabled` | tfvars or `export TF_VAR_avi_enabled=false` | `true` (default) for AVI LB regions; `false` for NSX_LB regions — omits `loadBalancerVPCEndpoint` from VPC spec |

**Required for `apply-bootstrap`** (`kubeconfigs` and `namespace_config` are passed automatically by the Makefile from infra outputs):

| Variable | How to set | Description |
|----------|-----------|-------------|
| `repo_url` | `export TF_VAR_repo_url=https://github.com/your-org/argocd-scaffolding` | GitOps repo URL injected into the root ArgoCD Application; defaults to `https://github.com/warroyo/argocd-scaffolding` (same default as the Helm chart) — **set this before running terraform if you forked/moved the repo** |
| `argo_password` | `export TF_VAR_argo_password=...` | ArgoCD admin password (bcrypt hash); optional, defaults to `""` |

**Optional — enable AKO secret:**

| Variable | How to set | Description |
|----------|-----------|-------------|
| `ako_secret_enabled` | tfvars or `export TF_VAR_ako_secret_enabled=true` | Create the AKO secret in each namespace |
| `ako_username` | `export TF_VAR_ako_username=...` | Base64-encoded AVI username |
| `ako_password` | `export TF_VAR_ako_password=...` | Base64-encoded AVI password |
| `ako_ca_data` | `export TF_VAR_ako_ca_data=...` | Base64-encoded Root CA for AVI |

### Backend Configuration

Both Terraform roots (`terraform/infra`, `terraform/bootstrap`) use the **Kubernetes
backend** — state is stored as a `Secret` in a dedicated supervisor namespace, so runs
are portable across machines/CI. The two roots use distinct `secret_suffix` values
(`infra`, `bootstrap`) and share one namespace.

**One-time bootstrap** — create the project + state namespace out-of-band against the
org CCI kubeconfig (the supervisor namespace uses `generateName`, so use `create`, not
`apply`, and capture the generated name):
```sh
kubectl --kubeconfig <org-CCI-kubeconfig> apply -f terraform/state-namespace/project.yaml
NAME=$(kubectl --kubeconfig <org-CCI-kubeconfig> create \
  -f terraform/state-namespace/state-namespace.yaml -o jsonpath='{.metadata.name}')
echo "namespace = \"$NAME\"" > terraform/state-backend/namespace.auto.tfvars   # commit this
```

**How init works** — `make init-infra` / `init-bootstrap` first run `make state-backend`
(the stateless `terraform/state-backend` helper), which pulls a fresh namespace kubeconfig
and renders the gitignored `terraform/{infra,bootstrap}/backend-k8s.hcl`. `init` is then
run with `-backend-config=backend-k8s.hcl`. The helper re-reads the kubeconfig live each
run, so the token is never stale. `make state-backend` needs the same vcfa `TF_VAR_*` as
`apply-infra`.

**Override** — set `BACKEND_CONFIG` to a different `-backend-config` file to bypass the
generated one (e.g. a local `path = "terraform.tfstate"` for throwaway local runs).

### First-time Setup

1. Clone this repo and `cd` into it.
2. Edit `terraform/infra/tenants.yaml` — add your infra tenant and at least one namespace with `deploy_argo: true`.
3. Update `argocd/repo-config.yaml` with your GitOps repo URL.
4. Export required env vars (or create `terraform/infra/terraform.tfvars` for non-sensitive ones).
5. Run:
   ```sh
   make apply-infra BACKEND_CONFIG=terraform/infra/backend-local.hcl
   ```
   This provisions namespaces and renders generated files (`argocd/projects/`, `infrastructure/clusters/*/vars/`, `terraform/bootstrap/{providers,main}.tf`).
6. Commit the rendered files.
7. Run:
   ```sh
   make apply-bootstrap BACKEND_CONFIG=terraform/infra/backend-local.hcl
   ```
   This deploys the ArgoCD Helm chart and root Application into each namespace with `deploy_argo: true`.
8. Verify with `make validate` — build-tests every Kustomize entrypoint.

---

## Overview

The project follows a **GitOps** workflow where the entire state of the infrastructure and applications is defined in this repository. There are two distinct lifecycles:

- **Tenant management** — driven by `terraform/infra/tenants.yaml` and Terraform. Provisions supervisor namespaces, quotas, bootstraps the ArgoCD instance, and renders all generated config (ArgoCD projects, tenant vars, bootstrap wiring).
- **Cluster management** — driven by GitOps. Hand-authored cluster directories under `infrastructure/clusters/{project}/{namespace_ref}/{cluster}/` are auto-discovered by ArgoCD ApplicationSets via a label-based decision model.

### Key Technologies

- **Terraform**: Provisions vSphere supervisor namespaces, bootstraps ArgoCD via Helm, and renders all generated config from `tenants.yaml` via `local_file`/`templatefile` (no Python, no ytt).
- **Helm**: Used by Terraform to deploy the `bootstrap-tenant` chart (ArgoCD instance + root app).
- **ArgoCD**: GitOps engine managing the lifecycle of clusters and applications via the App of Apps pattern.
- **Kustomize**: Structures Kubernetes manifests using Base/Components/Profiles with variable injection. Clusters inherit an environment **profile** and add only their own deltas, so fleet-wide changes happen in one place while per-cluster overrides stay easy.
- **GitHub Actions**: CI/CD for running `make apply` on tenant changes (which also renders + commits generated files).
- **AKO (Avi Kubernetes Operator)**: Configured as an infrastructure addon for load balancing.

## Directory Structure

- `terraform/`
  - `infra/`: Provisions vSphere supervisor namespaces, outputs kubeconfigs, and renders all generated config from `tenants.yaml` (`generate.tf` + `templates/*.tftpl`).
  - `bootstrap/`: Deploys the `bootstrap-tenant` Helm chart into each namespace. `providers.tf`/`main.tf` are rendered by the infra run; `locals.tf` (hand-authored) merges secrets into the infra run's `namespace_config` output (which carries the suffixed namespace names + `gitops.platform/*` labels).
  - `modules/bootstrap-helm/`: Terraform module wrapping the bootstrap Helm chart (single `config` object input).
  - `modules/tenant/`, `modules/svns/`, `modules/vpc/`: vSphere infrastructure modules.
- `charts/bootstrap-tenant/`: Helm chart that deploys the `ArgoNamespace` registration, ArgoCD instance + root Application.
- `argocd/`
  - `appsets/`: ApplicationSets that discover and deploy clusters and apps (label-based join).
  - `projects/`: ArgoCD AppProject definitions, all rendered by the infra run (the `infra`-type tenant's project is rendered as `infra.yaml`, the project the ApplicationSets target).
  - `repo-config.yaml`: Single source of truth for the GitOps repo URL.
- `infrastructure/`
  - `base/`: Reusable base Kustomize configs (e.g., `ako`, `antrea`, `vks-cluster`). Bases carry `replace-me` placeholders for environment values.
  - `components/`: Kustomize components for optional features and environment overlays (`envs/{env}` carries the real per-environment values).
  - `profiles/{env}/`: The inherited default set for an environment — bases + always-on components + the env overlay. Clusters reference a profile instead of enumerating everything.
  - `clusters/{project}/{namespace_ref}/{cluster}/`: Per-cluster definitions (`kustomization.yaml`, `apps/kustomization.yaml`, `cluster-details.yaml`). Each references a profile and adds only deltas + override patches. `clusters/{project}/vars/` holds the Terraform-rendered `tenant-vars.yaml`.
- `apps/`
  - `base/`: Base application manifests.
  - `components/stacks/`: Application stacks (e.g., `standard`, `observability`).
  - `components/envs/{env}/`: Feature-scoped per-environment app tuning (e.g., `envs/dev/istio`), included only alongside the matching stack.
  - `profiles/{env}/`: The inherited default app stack for an environment.
- `docs/examples/`
  - `cluster-template/`: Copy-me template for onboarding a new cluster.
  - `sample-tenant-repo/`: Example of what a tenant keeps in their **own** app repo (not deployed by this platform).
- `.github/workflows/`
  - `apply.yml`: On tenant changes, runs `make apply-infra` (provisions + renders generated files), commits them, then runs `make apply-bootstrap`.
  - `validate.yml`: On PRs and pushes to `main`, runs `scripts/validate.sh` — the same build-test you run locally with `make validate` (renders every cluster (infra + apps) and the argocd root with kustomize, and checks each `cluster-details.yaml` matches its directory path).

## Local Testing

Before pushing, build-test every kustomize entrypoint the same way CI does:

```sh
make validate        # or: ./scripts/validate.sh
```

It renders the argocd root and every cluster (infra + `apps/`) with kustomize and verifies
each `cluster-details.yaml` matches its directory path. Requires `kustomize` on your PATH.

### Running the GitHub Actions workflows locally with `act`

You can run the workflows in `.github/workflows/` locally with
[`act`](https://github.com/nektos/act) (requires Docker). Repo defaults live in
`.actrc` (pins the `catthehacker/ubuntu:act-latest` runner image).

```sh
# validate.yml — safe, no secrets (mirrors `make validate`)
act pull_request -W .github/workflows/validate.yml

# apply.yml — runs real terraform apply against live infrastructure
act push -W .github/workflows/apply.yml --secret-file .secrets
```

`apply.yml` needs the same secrets CI uses — copy them into `.secrets` (gitignored;
see the placeholders in that file). State now lives in the Kubernetes backend, so the
state-namespace must already exist and `terraform/state-backend/namespace.auto.tfvars`
must hold its name (see **Backend Configuration**); the workflow's `state-backend` step
fetches the kubeconfig at run time from the vcfa creds. Optionally set `GITHUB_TOKEN` in
`.secrets` to let the workflow's `git push` step push regenerated files. **`act push` on
`apply.yml` mutates live infrastructure.**

## Tenant Types

- **`type: infra`** — The platform tenant that hosts the ArgoCD instance. Generates an unrestricted ArgoCD project (`namespaceResourceWhitelist: */*`). Only one infra tenant is supported, but it may have multiple namespaces each with `deploy_argo: true`. The `infra` project owns all cluster provisioning (ApplicationSets use `project: infra`).
- **`type: tenant`** — Developer tenants. Each gets a dedicated ArgoCD project for deploying apps into their clusters. (The current template grants broad permissions; tightening `sourceRepos`/resource whitelists per tenant is a recommended follow-up.)

## Workflows

### 1. Bootstrapping a New Tenant

1. Add a new entry to `terraform/infra/tenants.yaml`. Required per-namespace fields:
   - `environment` — selects the Kustomize profile (`dev`, `prod`, …)
   - `zone_name` — vSphere zone for the namespace (a default of `z-wld-a` exists but **always set this explicitly** — zone names vary per region)
2. Run `make apply` (or push to `main` — the Apply workflow runs it). `apply-infra`:
   - provisions the supervisor namespace(s), and
   - renders `argocd/projects/{tenant}.yaml`, the projects kustomization,
     `infrastructure/clusters/{tenant}/vars/{tenant-vars,kustomization}.yaml`
     (with the auto-generated `tenant_uuid`, `vpc_name`, `argo_namespace`), and
     `terraform/bootstrap/{providers,main}.tf`.
3. Commit those generated files; then bootstrap deploys the Helm chart and ArgoCD.

### 2. Provisioning a New Cluster

1. Copy the template into place:
   ```sh
   cp -r docs/examples/cluster-template \
     infrastructure/clusters/{project}/{namespace_ref}/{cluster}
   ```
2. Edit `cluster-details.yaml` so `cluster_name`, `project`, and `namespace_ref`
   match the directory path (`namespace_ref` matches a namespace `name` in
   `tenants.yaml` and must be unique per project). The `validate.yml` workflow
   enforces this match on every PR.
3. Set the environment by referencing the right profile (`profiles/{env}`) in
   both `kustomization.yaml` and `apps/kustomization.yaml`. Add only the optional
   feature components / app stacks this cluster needs, and any override patches —
   everything else is inherited from the profile. Keep `cluster-var-injector`
   **last** in the infra component list.
4. Commit. The `cluster-provisioning` ApplicationSet joins the directory to its
   supervisor namespace by label (`gitops.platform/project` +
   `gitops.platform/namespace-ref`) and provisions it. The vcfa-generated
   namespace name is resolved from the cluster registration, not from git.

### 3. Deploying Applications

1. Define app bases in `apps/base/`.
2. Group apps into stacks in `apps/components/stacks/`.
3. Enable stacks for a cluster by editing its `apps/kustomization.yaml`.
4. ArgoCD syncs the `cluster-apps` ApplicationSet and deploys the assigned apps.

## Inheritance model (profiles, components, overrides)

A cluster does not enumerate its whole stack. It references an environment
**profile** and layers deltas on top:

- **Profile** (`infrastructure/profiles/{env}`, `apps/profiles/{env}`): the
  always-on set for an environment — bases + always-on feature components + the
  env overlay that carries the real per-environment values. Change something for
  every cluster in an environment by editing the profile once.
- **Deltas**: a cluster adds optional feature components (`istio`, `ako-istio`,
  `cluster-autoscaling`, …) and app stacks (`observability`) that aren't part of
  the baseline.
- **Overrides**: anything inherited can be overridden per-cluster with a
  `patches:` block in the cluster `kustomization.yaml` (escape hatch).

Because everything resolves through plain Kustomize, `kustomize build <cluster-dir>`
reproduces exactly what ArgoCD deploys — env selection is an explicit profile
reference, never injected at sync time.

## AKO Configuration

AKO is configured as a modular Kustomize component.

- **Base**: `infrastructure/base/ako` defines `AddonConfig` and `AddonInstall` with `replace-me` placeholders for environment values.
- **Variable injection**: `cluster-var-injector` injects `cluster_name`/`project` (from `cluster-details.yaml`) and `tenant_uuid`/`vpc_name`/`argo_namespace` (from `tenant-vars.yaml`). It must run **last** so it rewrites resources pulled in by the profile and the feature components.
- **Environment overlays**: `infrastructure/components/envs/{env}` owns the real `controllerHost`/`cloudName` values and is applied via the profile, so a cluster that skips it fails loudly instead of running on stale defaults.
- **Istio integration**: `infrastructure/components/ako-istio` enables Istio support (include `istio` + `ako-istio` in the cluster `kustomization.yaml`).

## Label-based provisioning (decision model)

Each supervisor namespace registers to ArgoCD with `clusterLabels` (computed in
`terraform/infra/main.tf` and passed to the bootstrap run via the
`namespace_config` output):

| Label | Source | Role |
|-------|--------|------|
| `type: supervisor-ns` | computed | coarse selector |
| `gitops.platform/project` | tenant name | join key (== top dir) |
| `gitops.platform/namespace-ref` | namespace name | join key (== 2nd dir); unique per project |
| `gitops.platform/environment` | namespace `environment` | decision dimension |
| `gitops.platform/namespace` | vcfa-suffixed name, captured by the chart | supplies `destination.namespace` |

A cluster directory `infrastructure/clusters/{project}/{namespace_ref}/{cluster}/`
is provisioned into the supervisor namespace whose labels match its
`(project, namespace_ref)`. The `cluster-provisioning` ApplicationSet templates the
git path with those label values, so the match is exact and collision-free. The
workload `ArgoCluster` registrations carry the same join keys (plus
`type: tenant`), so `cluster-apps` joins exactly too.

## Auto-Generated Values

Some values are only known after Terraform runs and are rendered by the infra run
into `infrastructure/clusters/{tenant}/vars/tenant-vars.yaml`:

| Value | Source |
|-------|--------|
| `tenant_uuid` | K8s UID of the vSphere Project CRD |
| `vpc_name` | `{tenant}-{region}-vpc` |
| `argo_namespace` | vSphere-generated infra namespace ID |

The supervisor namespace's own suffixed name is **not** written to git — it is carried
as the `gitops.platform/namespace` cluster label and consumed at sync time.

## Repo URL Configuration

The GitOps repo URL is defined in one place: `argocd/repo-config.yaml`. Kustomize replacements inject it into all ApplicationSets at apply time. When forking or moving this repo, update only that file.

For the bootstrap Helm chart, set `TF_VAR_repo_url` **before** running `make apply-bootstrap` (defaults to `https://github.com/warroyo/argocd-scaffolding`, same as `charts/bootstrap-tenant/values.yaml`'s `repoURL` — both must be updated together when forking).
