variable "namespace" {
  type        = string
  description = "The namespace to bootstrap"
}

variable "tenant_name" {
  type        = string
  description = "The tenant name"
}

variable "deploy_argo" {
  type        = bool
  description = "Whether to deploy ArgoCD in this namespace"
  default     = false
}

variable "argo_namespace" {
  type        = string
  description = "The ArgoCD namespace that manages this tenant"
}

variable "argo_password" {
  type        = string
  description = "ArgoCD admin password (bcrypt hash required by chart if used)"
  sensitive   = true
  default     = ""
}

variable "argo_cluster_labels" {
  type        = map(string)
  description = "Labels to apply to the ArgoCD cluster"
  default = {
    type = "tenant"
  }
}

variable "root_app_url" {
  type        = string
  description = "URL of the root app repo"
  default     = "https://github.com/warroyo/argocd-scaffolding"
}

variable "root_app_path" {
  type        = string
  description = "Path to the root app in the repo"
  default     = "argocd"
}

variable "root_app_revision" {
  type        = string
  description = "Target revision for the root app"
  default     = "main"
}
