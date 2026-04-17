# ArgoCD Scaffolding Project

This repository contains the infrastructure and application configuration for managing a multi-tenant Kubernetes environment using ArgoCD, Terraform, and Kustomize.

## Overview

The project follows a **GitOps** workflow where the entire state of the infrastructure and applications is defined in this repository. There are two distinct lifecycles:

- **Tenant management** — driven by `terraform/infra/tenants.yaml` and Terraform. Provisions supervisor namespaces, quotas, and bootstraps the ArgoCD instance.
- **Cluster management** — driven by GitOps. Cluster directories under `infrastructure/clusters/` are auto-discovered by ArgoCD ApplicationSets.

### Key Technologies

- **Terraform**: Provisions vSphere supervisor namespaces and bootstraps ArgoCD via Helm.
- **Helm**: Used by Terraform to deploy the `bootstrap-tenant` chart (ArgoCD instance + root app).
- **ArgoCD**: GitOps engine managing the lifecycle of clusters and applications via the App of Apps pattern.
- **Kustomize**: Structures Kubernetes manifests using Base/Overlays with variable injection.
- **ytt**: Generates cluster Kustomize files from a single `cluster-values.yaml` per cluster.
- **Python scripts**: Code generation from `tenants.yaml` (ArgoCD projects, Terraform providers/modules, tenant vars).
- **GitHub Actions**: CI/CD for running `make generate` on config changes and `make apply` on tenant changes.
- **AKO (Avi Kubernetes Operator)**: Configured as an infrastructure addon for load balancing.

## Directory Structure

- `terraform/`
  - `infra/`: Provisions vSphere supervisor namespaces and outputs kubeconfigs. Reads `tenants.yaml`.
  - `bootstrap/`: Deploys the `bootstrap-tenant` Helm chart into each namespace. Generated from `tenants.yaml`.
  - `modules/bootstrap-helm/`: Terraform module wrapping the bootstrap Helm chart.
  - `modules/tenant/`, `modules/svns/`, `modules/vpc/`: vSphere infrastructure modules.
- `charts/bootstrap-tenant/`: Helm chart that deploys ArgoCD instance + root Application.
- `scripts/`
  - `generate-bootstrap.py`: Generates `terraform/bootstrap/providers.tf` and `main.tf` from `tenants.yaml`.
  - `generate-tenants.py`: Generates ArgoCD AppProject files (via ytt `templates/tenant/project.yaml`) and `argocd/projects/kustomization.yaml` (via ytt `templates/tenant/kustomization.yaml`) and `infrastructure/clusters/{tenant}/vars/kustomization.yaml` stubs from `tenants.yaml`.
  - `generate-clusters.py`: Renders cluster kustomization files via ytt (`templates/cluster/`) for each cluster. Preserves `namespace`/`argo_namespace` in `cluster-details.yaml` across regenerations.
  - `generate-details.py`: Post-Terraform — populates `tenant-vars.yaml` and fills `namespace`/`argo_namespace` in `cluster-details.yaml` from Terraform outputs.
- `templates/cluster/`: ytt templates for cluster files. Processed per cluster from `cluster-values.yaml`.
- `templates/tenant/`: ytt templates for tenant ArgoCD AppProject files. Rendered by `generate-tenants.py`.
- `argocd/`
  - `appsets/`: ApplicationSets that discover and deploy clusters and apps.
  - `projects/`: ArgoCD AppProject definitions (generated from `tenants.yaml`).
  - `root/`: Root Application bootstrapped by Terraform.
  - `repo-config.yaml`: Single source of truth for the GitOps repo URL.
- `infrastructure/`
  - `base/`: Reusable base Kustomize configs (e.g., `ako`, `antrea`, `vks-cluster`).
  - `components/`: Kustomize components for optional features and environment overlays.
  - `clusters/`: Per-cluster definitions. Each cluster has a `cluster-values.yaml` (source) and generated files.
- `apps/`
  - `base/`: Base application manifests.
  - `components/stacks/`: Application stacks (e.g., `standard`, `observability`, `service-mesh`).
  - `clusters/`: Cluster-specific app aggregations.
- `.github/workflows/`
  - `generate.yml`: Runs `make generate` on config changes and commits results.
  - `apply.yml`: Runs `make apply` on tenant changes and commits auto-generated namespace IDs.

## Tenant Types

- **`type: infra`** — The platform tenant that hosts the ArgoCD instance. Generates an unrestricted ArgoCD project (`namespaceResourceWhitelist: */*`). Only one infra tenant is supported, but it may have multiple namespaces each with `deploy_argo: true`. The `infra` project owns all cluster provisioning (ApplicationSets use `project: infra`).
- **`type: tenant`** — Developer tenants. Each gets a locked-down ArgoCD project for deploying apps into their clusters.

## Workflows

### 1. Bootstrapping a New Tenant

1. Add a new entry to `terraform/infra/tenants.yaml`.
2. Run `make generate` (or push — GitHub Actions runs it automatically) to regenerate:
   - `terraform/bootstrap/providers.tf` and `main.tf`
   - `argocd/projects/{tenant}.yaml`
   - `infrastructure/clusters/{tenant}/vars/kustomization.yaml`
3. Run `make apply` to provision the supervisor namespace and deploy the bootstrap Helm chart.
   - After Terraform completes, `make generate-details` runs automatically to populate `tenant-vars.yaml` with the auto-generated `tenant_uuid` and `vpc_name`.

### 2. Provisioning a New Cluster

1. Create `infrastructure/clusters/{tenant}/{cluster}/cluster-values.yaml`:
   ```yaml
   #@data/values
   ---
   cluster_name: my-cluster
   project: tenant-1
   namespace_ref: dev-1       # matches a namespace name in tenants.yaml
   env: dev
   features:
     istio: true
     autoscaling: false
     ha_control_plane: false
     service_mesh: false
     observability: true
   ```
2. Run `make generate` (or push) to render the cluster's `kustomization.yaml`, `apps/kustomization.yaml`, and `cluster-details.yaml` (via `generate-clusters.py`).
3. Run `make generate-details` (or `make apply-infra`) to fill in the vSphere-generated `namespace` and `argo_namespace` fields in `cluster-details.yaml`.
4. Commit the generated files. The `cluster-provisioning` ApplicationSet detects the new `cluster-details.yaml` and creates the cluster automatically.

### 3. Deploying Applications

1. Define app bases in `apps/base/`.
2. Group apps into stacks in `apps/components/stacks/`.
3. Enable stacks for a cluster by setting feature flags in `cluster-values.yaml` and re-running `make generate`.
4. ArgoCD syncs the `cluster-apps` ApplicationSet and deploys the assigned apps.

## AKO Configuration

AKO is configured as a modular Kustomize component.

- **Base**: `infrastructure/base/ako` defines `AddonConfig` and `AddonInstall`.
- **Variable injection**: `cluster-var-injector` injects `cluster_name` (from `cluster-details.yaml`) and `tenant_uuid`/`vpc_name` (from `tenant-vars.yaml`).
- **Environment overlays**: `infrastructure/components/envs/{env}` patches environment-specific settings.
- **Istio integration**: `infrastructure/components/ako-istio` enables Istio support (enabled via `features.istio: true` in `cluster-values.yaml`).

## Auto-Generated Values

Some values are only known after Terraform runs and are populated by `scripts/generate-details.py`:

| Value | Source | Written to |
|-------|--------|-----------|
| `namespace` | vSphere-generated supervisor namespace ID | `cluster-details.yaml` |
| `argo_namespace` | vSphere-generated infra namespace ID | `cluster-details.yaml` |
| `tenant_uuid` | K8s UID of the vSphere Project CRD | `tenant-vars.yaml` |
| `vpc_name` | `{tenant}-{region}-vpc` | `tenant-vars.yaml` |

## Repo URL Configuration

The GitOps repo URL is defined in one place: `argocd/repo-config.yaml`. Kustomize replacements inject it into all ApplicationSets at apply time. When forking or moving this repo, update only that file.

For the bootstrap Helm chart, set `TF_VAR_repo_url` before running `make apply-bootstrap`.
