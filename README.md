# ArgoCD Scaffolding Project

This repository contains the infrastructure and application configuration for managing a multi-tenant Kubernetes environment using ArgoCD, Terraform, and Kustomize.

## Overview

The project follows a **GitOps** workflow where the entire state of the infrastructure and applications is defined in this repository. There are two distinct lifecycles:

- **Tenant management** — driven by `terraform/infra/tenants.yaml` and Terraform. Provisions supervisor namespaces, quotas, and bootstraps the ArgoCD instance.
- **Cluster management** — driven by GitOps. Cluster directories under `infrastructure/clusters/` are auto-discovered by ArgoCD ApplicationSets.

### Key Technologies

- **Terraform**: Provisions vSphere supervisor namespaces, bootstraps ArgoCD via Helm, and generates GitOps config files.
- **Helm**: Used by Terraform to deploy the `bootstrap-tenant` chart (ArgoCD instance + root app).
- **ArgoCD**: GitOps engine managing the lifecycle of clusters and applications via the App of Apps pattern.
- **Kustomize**: Structures Kubernetes manifests using Base/Overlays with variable injection.
- **Python + Jinja2**: Generates `terraform/bootstrap/` HCL from `tenants.yaml` via Jinja2 templates.
- **GitHub Actions**: CI/CD for running `make generate` on config changes and `make apply` on tenant changes.
- **AKO (Avi Kubernetes Operator)**: Configured as an infrastructure addon for load balancing.

## Directory Structure

- `terraform/`
  - `infra/`: Provisions vSphere supervisor namespaces and outputs kubeconfigs. Reads `tenants.yaml`. Also writes `namespace-details.yaml` and `tenant-vars.yaml` into the cluster tree during apply.
  - `bootstrap/`: Deploys the `bootstrap-tenant` Helm chart into each namespace. Generated from `tenants.yaml`.
  - `generate/`: Terraform module (local provider only) that writes AppProject YAMLs and `vars/kustomization.yaml` stubs from `tenants.yaml`. Run via `make generate`.
  - `modules/bootstrap-helm/`: Terraform module wrapping the bootstrap Helm chart.
  - `modules/tenant/`, `modules/svns/`, `modules/vpc/`: vSphere infrastructure modules.
- `charts/bootstrap-tenant/`: Helm chart that deploys ArgoCD instance + root Application.
- `scripts/`
  - `generate-bootstrap.py`: Generates `terraform/bootstrap/providers.tf` and `main.tf` from `tenants.yaml` via Jinja2 templates in `templates/bootstrap/`.
- `templates/bootstrap/`: Jinja2 templates for bootstrap Terraform HCL. Rendered by `generate-bootstrap.py`.
- `templates/tenant/`: Terraform `templatefile()` templates for AppProject YAMLs, kustomization stubs, and post-infra ConfigMaps.
- `templates/cluster/`: Static scaffold templates for new clusters. Copy to a cluster directory and set `cluster_name` in `kustomization.yaml`.
- `argocd/`
  - `appsets/`: ApplicationSets that discover and deploy clusters and apps.
  - `projects/`: ArgoCD AppProject definitions (generated from `tenants.yaml`).
  - `root/`: Root Application bootstrapped by Terraform.
  - `repo-config.yaml`: Single source of truth for the GitOps repo URL.
- `infrastructure/`
  - `base/`: Reusable base Kustomize configs (e.g., `ako`, `antrea`, `vks-cluster`).
  - `components/`: Kustomize components for optional features and environment overlays.
  - `clusters/`: Per-cluster definitions at `{tenant}/{namespace-id}/{cluster}/`. Each cluster has `kustomization.yaml`; each namespace has `namespace-details.yaml` (Terraform-generated).
- `apps/`
  - `base/`: Base application manifests.
  - `components/stacks/`: Application stacks (e.g., `standard`, `observability`, `service-mesh`).
- `.github/workflows/`
  - `generate.yml`: Runs `make generate` on config changes and commits results.
  - `apply.yml`: Runs `make apply` on tenant changes and commits auto-generated files.

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
   - After Terraform completes, `tenant-vars.yaml` is written automatically to `infrastructure/clusters/{tenant}/vars/`.

### 2. Provisioning a New Cluster

1. Run `make apply-infra` to ensure the namespace directory exists:
   ```
   infrastructure/clusters/{tenant}/{namespace-id}/
     namespace-details.yaml   ← written by Terraform (namespace, argo_namespace, tenant)
   ```
   Commit the new namespace-details.yaml.

2. Copy the cluster template and set the ONE required value:
   ```bash
   cp -r templates/cluster infrastructure/clusters/{tenant}/{namespace-id}/{cluster}
   # Edit kustomization.yaml: set cluster_name={cluster} in the configMapGenerator literal
   ```

3. Uncomment optional components in `kustomization.yaml` as needed (istio, autoscaling, etc.)
   and in `apps/kustomization.yaml` (observability, service-mesh stacks).

4. Commit. The `cluster-provisioning` ApplicationSet detects the new cluster directory and creates the Application automatically.

### 3. Deploying Applications

1. Define app bases in `apps/base/`.
2. Group apps into stacks in `apps/components/stacks/`.
3. Enable stacks for a cluster by uncommenting them in `apps/kustomization.yaml` and re-committing.
4. ArgoCD syncs the `cluster-apps` ApplicationSet and deploys the assigned apps.

## Cluster Data Flow

Each cluster's kustomization layer uses three ConfigMaps for variable injection via `cluster-var-injector`:

| ConfigMap | Source | Fields | Used for |
|-----------|--------|--------|----------|
| `cluster-id` | inline `configMapGenerator` in `kustomization.yaml` | `cluster_name` | VKS Cluster name, AKO config, AddonInstall selectors |
| `namespace-details` | `../namespace-details.yaml` (Terraform-generated) | `namespace`, `argo_namespace`, `tenant` | Resource namespace, ArgoCD attach project/argoNamespace |
| `tenant-vars` | `../../../vars/tenant-vars.yaml` (Terraform-generated) | `tenant_uuid`, `vpc_name` | AKO network settings |

The ArgoCD `cluster-provisioning` ApplicationSet uses a git **directory** generator on `infrastructure/clusters/*/*/*`. It derives the Application name, project, and destination namespace directly from path segments — no per-cluster metadata file is read.

## AKO Configuration

AKO is configured as a modular Kustomize component.

- **Base**: `infrastructure/base/ako` defines `AddonConfig` and `AddonInstall`.
- **Variable injection**: `cluster-var-injector` injects `cluster_name` (from `cluster-id` ConfigMap) and `tenant_uuid`/`vpc_name` (from `tenant-vars` ConfigMap).
- **Environment overlays**: `infrastructure/components/envs/{env}` patches environment-specific settings.
- **Istio integration**: `infrastructure/components/ako-istio` enables Istio support (uncomment in `kustomization.yaml`).

## Auto-Generated Values

These values are written to git by `make apply-infra` (Terraform's `local_file` resources in `terraform/infra/generate-details.tf`):

| Value | Source | Written to |
|-------|--------|-----------|
| `namespace` | vSphere-generated supervisor namespace ID | `namespace-details.yaml` |
| `argo_namespace` | vSphere-generated infra namespace ID | `namespace-details.yaml` |
| `tenant` | Tenant name from `tenants.yaml` | `namespace-details.yaml` |
| `tenant_uuid` | K8s UID of the vSphere Project CRD | `tenant-vars.yaml` |
| `vpc_name` | `{tenant}-{region}-vpc` | `tenant-vars.yaml` |

## Repo URL Configuration

The GitOps repo URL is defined in one place: `argocd/repo-config.yaml`. Kustomize replacements inject it into all ApplicationSets at apply time. When forking or moving this repo, update only that file.

For the bootstrap Helm chart, set `TF_VAR_repo_url` before running `make apply-bootstrap`.
