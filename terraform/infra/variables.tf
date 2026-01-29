variable "vcfa_refresh_token" {
  type        = string
  description = "The VCF Automation refresh token"
  sensitive   = true
}

variable "vcfa_url" {
  type        = string
  description = "The VCF Automation url"
}

variable "vcfa_org" {
  type        = string
  description = "The VCF Automation org"
}

variable "argo_password" {
  type = string
  sensitive = true
  default = ""
}

variable "infra_project" {
  type        = string
  default = "infra-1"
}

variable "supervisor_namespace" {
  type        = string
}
variable "root_app" {
  type        = string
  default     = "https://raw.githubusercontent.com/warroyo/argocd-scaffolding/refs/heads/main/argocd/root/root.yaml"
  description = "The raw URL of the file to pull from Git"
}