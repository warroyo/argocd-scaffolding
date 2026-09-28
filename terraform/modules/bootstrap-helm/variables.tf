variable "config" {
  description = "Per-namespace bootstrap configuration (built in terraform/bootstrap/locals.tf)."
  type = object({
    namespace      = string
    tenant_name    = string
    deploy_argo    = bool
    cluster_labels = map(string)
    repo_url       = string
    argo_password  = string
  })
}
