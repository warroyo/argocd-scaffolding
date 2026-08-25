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

variable "region_name" {
  type = string
}

variable "avi_enabled" {
  type        = bool
  description = "Whether the region uses AVI as its load balancer. Set false for NSX_LB regions."
  default     = false
}

variable "seg_name" {
  type        = string
  description = "Service Engine Group associated with each Supervisor Namespace. Required when avi_enabled is true (NSX_REGISTERED_AVI LB regions); leave null for NSX_LB regions."
  default     = null
}
