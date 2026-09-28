variable "config" {
  description = "Per-namespace bootstrap configuration (built in terraform/bootstrap/locals.tf)."
  type = object({
    namespace   = string
    deploy_argo = bool
    managed_namespaces = list(object({
      name    = string
      project = string
      labels  = map(string)
    }))
    repo_url      = string
    argo_password = string
  })
}
