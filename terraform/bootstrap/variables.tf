variable "kubeconfigs" {
  type = map(object({
    host                     = string
    token                    = string
    insecure_skip_tls_verify = bool
  }))
  description = "Map of namespace key to kubeconfig — output of the infra module. Passed automatically by the Makefile."
  sensitive   = true
}

variable "argo_password" {
  type        = string
  description = "ArgoCD admin password (bcrypt hash required by chart if used)"
  sensitive   = true
  default     = ""
}

variable "ako_secret_enabled" {
  type        = bool
  description = "Whether to create the AKO secret"
  default     = false
}

variable "ako_username" {
  type        = string
  description = "Base64 encoded AVI username"
  sensitive   = true
  default     = ""
}

variable "ako_password" {
  type        = string
  description = "Base64 encoded AVI password"
  sensitive   = true
  default     = ""
}

variable "ako_ca_data" {
  type        = string
  description = "Base64 encoded Root CA Data"
  sensitive   = true
  default     = ""
}
