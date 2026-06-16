terraform {
  required_version = ">= 1.0"
  required_providers {
    vcfa = {
      source = "vmware/vcfa"
    }
    local = {
      source = "hashicorp/local"
    }
  }
}

provider "vcfa" {
  url                  = var.vcfa_url
  allow_unverified_ssl = true
  org                  = var.vcfa_org
  auth_type            = "api_token"
  api_token            = var.vcfa_refresh_token
}
