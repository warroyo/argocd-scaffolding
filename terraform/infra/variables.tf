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

variable "vcfa_oidc_audience" {
  type        = string
  description = <<-EOT
    The VCFA OIDC client id the vcf CLI's token carries (its `aud` claim) — the
    audience the guest apiserver trusts for the Headlamp bearer path
    (components/oidc-auth). Not a secret and not discoverable via TLS/discovery,
    so it is supplied here rather than derived. Read it off a live token:
      ./scripts/headlamp-token.sh | cut -d. -f2 | base64 -d | jq -r .aud
    Org-global. See docs/DECISIONS.md #21 (audience-width trade-off).
  EOT
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
