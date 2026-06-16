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

variable "project_name" {
  type        = string
  description = "CCI Project that owns the state supervisor namespace (see terraform/state-namespace/project.yaml)."
  default     = "tf-state"
}

variable "namespace" {
  type        = string
  description = <<-EOT
    The generated name of the state supervisor namespace (e.g. tf-state-bh7q6).
    Set in the committed namespace.auto.tfvars after the one-time `kubectl create`.
  EOT
}
