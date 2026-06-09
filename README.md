# ArgoCD Scaffolding Project

This repository contains the infrastructure and application configuration for managing a multi-tenant Kubernetes environment using ArgoCD, Terraform, and Kustomize.

## Overview

The project follows a **GitOps** workflow where the entire state of the infrastructure and applications is defined in this repository. There are two distinct lifecycles:

- **Tenant management** — driven by `terraform/infra/tenants.yaml` and Terraform. Provisions supervisor namespaces, quotas, bootstraps the ArgoCD instance, and renders all generated config (ArgoCD projects, tenant vars, bootstrap wiring).
- **Cluster management** — driven by GitOps. Hand-authored cluster directories under `infrastructure/clusters/{project}/{namespace_ref}/{cluster}/` are auto-discovered by ArgoCD ApplicationSets via a label-based decision model.

### Key Technologies

- **Terraform**: Provisions vSphere supervisor namespaces, bootstraps ArgoCD via Helm, and renders all generated config from `tenants.yaml` via `local_file`/`templatefile` (no Python, no ytt).
- **Helm**: Used by Terraform to deploy the `bootstrap-tenant` chart (ArgoCD instance + root app).
- **ArgoCD**: GitOps engine managing the lifecycle of clusters and applications via the App of Apps pattern.
- **Kustomize**: Structures Kubernetes manifests using Base/Overlays with variable injection. Cluster directories are hand-authored from shared components for full flexibility.
- **GitHub Actions**: CI/CD for running `make apply` on tenant changes (which also renders + commits generated files).
- **AKO (Avi Kubernetes Operator)**: Configured as an infrastructure addon for load balancing.

## Directory Structure

- `terraform/`
  - `infra/`: Provisions vSphere supervisor namespaces, outputs kubeconfigs, and renders all generated config from `tenants.yaml` (`generate.tf` + `templates/*.tftpl`).
  - `bootstrap/`: Deploys the `bootstrap-tenant` Helm chart into each namespace. `providers.tf`/`main.tf` are rendered by the infra run; `locals.tf` (hand-authored) reads `tenants.yaml` for per-namespace config + the `gitops.platform/*` labels.
  - `modules/bootstrap-helm/`: Terraform module wrapping the bootstrap Helm chart (single `config` object input).
  - `modules/tenant/`, `modules/svns/`, `modules/vpc/`: vSphere infrastructure modules.
- `charts/bootstrap-tenant/`: Helm chart that deploys the `ArgoNamespace` registration, ArgoCD instance + root Application.
- `argocd/`
  - `appsets/`: ApplicationSets that discover and deploy clusters and apps (label-based join).
  - `projects/`: ArgoCD AppProject definitions (per-tenant files rendered by the infra run; `infra.yaml` is static).
  - `root/`: Root Application bootstrapped by Terraform.
  - `repo-config.yaml`: Single source of truth for the GitOps repo URL.
- `infrastructure/`
  - `base/`: Reusable base Kustomize configs (e.g., `ako`, `antrea`, `vks-cluster`).
  - `components/`: Kustomize components for optional features and environment overlays.
  - `clusters/{project}/{namespace_ref}/{cluster}/`: Hand-authored per-cluster definitions (`kustomization.yaml`, `apps/kustomization.yaml`, `cluster-details.yaml`). `clusters/{project}/vars/` holds the Terraform-rendered `tenant-vars.yaml`.
- `apps/`
  - `base/`: Base application manifests.
  - `components/stacks/`: Application stacks (e.g., `standard`, `observability`, `service-mesh`).
  - `clusters/`: Cluster-specific app aggregations.
- `docs/examples/cluster-template/`: Copy-me template for onboarding a new cluster.
- `.github/workflows/`
  - `apply.yml`: On tenant changes, runs `make apply-infra` (provisions + renders generated files), commits them, then runs `make apply-bootstrap`.

## Tenant Types

- **`type: infra`** — The platform tenant that hosts the ArgoCD instance. Generates an unrestricted ArgoCD project (`namespaceResourceWhitelist: */*`). Only one infra tenant is supported, but it may have multiple namespaces each with `deploy_argo: true`. The `infra` project owns all cluster provisioning (ApplicationSets use `project: infra`).
- **`type: tenant`** — Developer tenants. Each gets a locked-down ArgoCD project for deploying apps into their clusters.

## Workflows

### 1. Bootstrapping a New Tenant

1. Add a new entry to `terraform/infra/tenants.yaml` (include a per-namespace `environment`).
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
   `tenants.yaml` and must be unique per project).
3. Edit `kustomization.yaml` / `apps/kustomization.yaml` to include the shared
   components and app stacks you want — full control, no generation step.
4. Commit. The `cluster-provisioning` ApplicationSet joins the directory to its
   supervisor namespace by label (`gitops.platform/project` +
   `gitops.platform/namespace-ref`) and provisions it. The vcfa-generated
   namespace name is resolved from the cluster registration, not from git.

### 3. Deploying Applications

1. Define app bases in `apps/base/`.
2. Group apps into stacks in `apps/components/stacks/`.
3. Enable stacks for a cluster by editing its `apps/kustomization.yaml`.
4. ArgoCD syncs the `cluster-apps` ApplicationSet and deploys the assigned apps.

## AKO Configuration

AKO is configured as a modular Kustomize component.

- **Base**: `infrastructure/base/ako` defines `AddonConfig` and `AddonInstall`.
- **Variable injection**: `cluster-var-injector` injects `cluster_name`/`project` (from `cluster-details.yaml`) and `tenant_uuid`/`vpc_name`/`argo_namespace` (from `tenant-vars.yaml`).
- **Environment overlays**: `infrastructure/components/envs/{env}` patches environment-specific settings (included by the cluster's hand-authored `kustomization.yaml`).
- **Istio integration**: `infrastructure/components/ako-istio` enables Istio support (include `istio` + `ako-istio` in the cluster `kustomization.yaml`).

## Label-based provisioning (decision model)

Each supervisor namespace registers to ArgoCD with `clusterLabels` (computed in
`terraform/bootstrap/locals.tf`):

| Label | Source | Role |
|-------|--------|------|
| `type: supervisor-ns` | `argo_labels` | coarse selector |
| `gitops.platform/project` | tenant name | join key (== top dir) |
| `gitops.platform/namespace-ref` | namespace name | join key (== 2nd dir); unique per project |
| `gitops.platform/environment` | namespace `environment` | decision dimension |
| `gitops.platform/namespace` | vcfa-suffixed name, captured by the chart | supplies `destination.namespace` |

A cluster directory `infrastructure/clusters/{project}/{namespace_ref}/{cluster}/`
is provisioned into the supervisor namespace whose labels match its
`(project, namespace_ref)`. The `cluster-provisioning` ApplicationSet templates the
git path with those label values, so the match is exact and collision-free.

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

For the bootstrap Helm chart, set `TF_VAR_repo_url` before running `make apply-bootstrap`.
