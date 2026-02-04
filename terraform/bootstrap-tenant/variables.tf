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
  description = "ArgoCD admin password"
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

variable "argo_version" {
  type        = string
  description = "ArgoCD version to deploy"
  default     = "3.0.19+vmware.1-vks.1"
}
