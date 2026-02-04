locals {
  vcf_access_token = jsondecode(data.http.get_vcf_token.response_body).access_token
}
resource "random_integer" "suffix" {
  min = 1
  max = 50000
}

resource "vra_blueprint" "namespace_bootstrap" {
  name        = "namespace-boostrap"
  description = "handles anything that needs to be created in a ns prior to argo"

  project_id = var.project_id
  request_scope_org = true

  content = <<-EOT
    formatVersion: 2
    inputs:
      namespace:
        title: Namespace
        type: string
      argo_namespace:
        title: Argo Namespace
        type: string
      argo_project:
        title: Argo Project
        type: string
      cluster_labels:
        title: Argo Cluster Labels
        type: object
        default:
          test: test
      deploy_argo:
        type: boolean
        title: deploy an argo cd instance?
        default: false
      argo_password:
        type: string
        title: argo cd admin password
        description: only used when deploying argo, must be bcrypt format
    resources:
      CCI_Supervisor_Namespace_1:
        type: CCI.Supervisor.Namespace
        properties:
          name: $${input.namespace}
          existing: true
      Argo_ns_attach:
        type: CCI.Supervisor.Resource
        properties:
          context: $${resource.CCI_Supervisor_Namespace_1.id}
          manifest:
            apiVersion: field.vmware.com/v1
            kind: ArgoNamespace
            metadata:
              name: $${resource.CCI_Supervisor_Namespace_1.name}
            spec:
              serviceAccount: ''
              argoNamespace: $${input.argo_namespace}
              clusterLabels: $${input.cluster_labels}
              project: $${input.argo_project}
      Argo_deploy:
        type: CCI.Supervisor.Resource
        dependsOn:
          - Argo_password
        properties:
          count: '$${input.deploy_argo ? 1 : 0}'
          context: $${resource.CCI_Supervisor_Namespace_1.id}
          manifest:
            apiVersion: argocd-service.vsphere.vmware.com/v1alpha1
            kind: ArgoCD
            metadata:
              name: argocd-infra
            spec:
              appplicationSet:
                enabled: true
              version: 3.0.19+vmware.1-vks.1
          wait:
            fields:
              - path: status.conditions[2].reason
                value: ReconcileSucceeded
                indicatesFailure: false
      Argo_password:
        type: CCI.Supervisor.Resource
        properties:
          count: '$${input.deploy_argo ? 1 : 0}'
          context: $${resource.CCI_Supervisor_Namespace_1.id}
          manifest:
            apiVersion: v1
            kind: Secret
            metadata:
              name: argocd-secret
            type: Opaque
            data:
              admin.password: $${base64_encode(input.argo_password)}

  EOT
}

resource "vra_blueprint_version" "ns-boostrap" {
  blueprint_id = vra_blueprint.namespace_bootstrap.id
  description  = "Released from vRA terraform provider"
  version      = (random_integer.suffix.result / random_integer.suffix.result)
  release      = true
  change_log   = "regular release"
}

data "vra_catalog_item" "catalog_item" {
  depends_on = [
    vra_blueprint_version.ns-boostrap
  ]

  name            = vra_blueprint.namespace_bootstrap.name
  project_id      = var.project_id
  expand_projects = true
  expand_versions = true
}

data "http" "get_vcf_token" {
  url      = "${var.vcfa_url}/oauth/tenant/${var.org}/token"
  method   = "POST"
  insecure = true

  request_body = "grant_type=refresh_token&refresh_token=${var.api_token}"
  request_headers = {
    "Content-Type" = "application/x-www-form-urlencoded"
    "Accept"       = "application/json"
  }
}


data "http" "assign_catalog_projects" {
  url    = "${var.vcfa_url}/catalog/api/items/${data.vra_catalog_item.catalog_item.id}:assign-projects"
  method = "POST"

  # We take all UIDs from our map and encode them into the required JSON payload
  request_body = jsonencode({
    projectsToAssign   = var.enabled_projects
    projectsToUnAssign = []
  })
  insecure = true

  request_headers = {
    Content-Type = "application/json"
    Authorization = "Bearer ${local.vcf_access_token}"
    "X-Terraform-Hash" = md5(jsonencode(var.enabled_projects))
  }
}

output "catalog_api_response" {
  value = {
    status_code = data.http.assign_catalog_projects.status_code
    body        = data.http.assign_catalog_projects.response_body
  }
  description = "The raw response from the Catalog Project Assignment API."
}

output "bp_version" {
  value = vra_blueprint_version.ns-boostrap.version
}

output "catalog_id" {
  value = data.vra_catalog_item.catalog_item.id
}