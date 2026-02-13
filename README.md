# ArgoCD Scaffolding Project

This repository contains the infrastructure and application configuration for managing a multi-tenant Kubernetes environment using ArgoCD, Terraform, and Kustomize.

## Overview

The project follows a **GitOps** workflow where the entire state of the infrastructure and applications is defined in this repository.

### Key Technologies
*   **Terraform/Terragrunt**: Used for bootstrapping the initial tenant infrastructure (Namespace, ArgoCD instance, RBAC).
*   **ArgoCD**: The GitOps engine that manages the lifecycle of clusters and applications.
*   **Helm**: Used by Terraform to deploy the initial bootstrap components.
*   **Kustomize**: Used for structuring and managing Kubernetes manifests with high reusability and composability (Base/Overlays pattern).
*   **AKO (Avi Kubernetes Operator)**: Configured as an infrastructure addon for load balancing.

## Directory Structure

*   `terraform/`: Terragrunt configurations for bootstrapping tenants and infrastructure.
    *   `modules/bootstrap-helm`: Terraform module that wraps the bootstrap Helm chart.
*   `charts/bootstrap-tenant/`: A local Helm chart used by Terraform to deploy:
    *   ArgoCD Instance
    *   Tenant Namespace
    *   Root App of Apps
*   `argocd/`: ArgoCD configuration for the "App of Apps" pattern.
    *   `appsets/`: ApplicationSets that dynamically discover and deploy clusters and apps.
    *   `projects/`: ArgoCD AppProject definitions (e.g., `infra`, `tenant-1`).
*   `infrastructure/`: Cluster infrastructure definitions (Clusters, Addons, CNIs).
    *   `base/`: Reusable base configurations (e.g., `ako`, `antrea`, `vks-cluster`).
    *   `components/`: Kustomize components for specific features or overlays.
        *   `ako/`: Base AKO component.
        *   `ako-istio/`: Overlay to enable Istio support in AKO.
        *   `envs/`: Environment-specific overlays (e.g., `dev` for AKO settings).
        *   `cluster-var-injector/`: Component to inject cluster variables into resources.
    *   `clusters/`: Cluster-specific definitions (e.g., `tenant-1/dev1-cluster`).
*   `apps/`: Application definitions.
    *   `base/`: Base application manifests.
    *   `components/`: Reusable application components and stacks.
    *   `clusters/`: Cluster-specific application aggregations.

## Workflows

### 1. Bootstrapping a New Tenant

1.  **Define Tenant**: Create a new directory in `terraform/tenants/<new-tenant>`.
2.  **Configure Terragrunt**: specific the `terragrunt.hcl` with tenant details (Namespace, ArgoCD settings).
3.  **Apply Terraform**: Run `terragrunt apply` to:
    *   Create the tenant namespace.
    *   Deploy the `bootstrap-tenant` Helm chart.
    *   This installs a dedicated ArgoCD instance and the "Root App".

### 2. Provisioning a New Cluster

1.  **Define Cluster**: Create a new directory `infrastructure/clusters/<tenant>/<cluster-name>`.
2.  **Cluster Config**: Create `cluster-details.yaml` and `kustomize.yaml`.
    *   `cluster-details.yaml`: Contains cluster-specific variables (e.g., `cluster_name`, `ako_controller_host`).
3.  **ArgoCD Discovery**: The `cluster-provisioning` ApplicationSet in `argocd/appsets` watches for `cluster-details.yaml` files.
4.  **Auto-Deployment**: ArgoCD automatically creates an Application to deploy the infrastructure defined in your new directory.

### 3. Deploying Applications

1.  **Define Apps**: Create application bases in `apps/base`.
2.  **Compose Stacks**: Group apps into stacks in `apps/components/stacks`.
3.  **Assign to Cluster**: In `apps/clusters/<tenant>/<cluster-name>/kustomization.yaml`, reference the desired stacks (e.g., `observability`, `service-mesh`).
4.  **ArgoCD Sync**: The `cluster-apps` ApplicationSet discovers the cluster configuration and deploys the assigned applications.

## AKO Configuration

AKO is configured as a modular component in the infrastructure layer.

*   **Base**: `infrastructure/base/ako` defines the core `AddonConfig` and `AddonInstall`.
*   **Variable Injection**:
    *   `cluster-var-injector` injects `cluster_name` from `cluster-details.yaml`.
    *   `cluster-var-injector` injects `tenant_uuid` and `vpc_name` from `tenant-vars.yaml`, dynamically constructing the NSX path.
*   **Environment Overlays**: `infrastructure/components/envs/<env>` patches environment-specific settings (Controller Host, Cloud Name, etc.).
*   **Istio Integration**: `infrastructure/components/ako-istio` optionally enables Istio support.

### Enabling AKO for a Cluster

In your cluster's `kustomization.yaml` (`infrastructure/clusters/<tenant>/<cluster>/kustomization.yaml`):

```yaml
components:
  - ../../../components/ako               # Base AKO
  - ../../../components/ako-istio         # Optional: Istio Support
  - ../../../components/cluster-var-injector # Required: Variable Injection
  - ../../../components/envs/dev          # Required: Environment Settings
```
