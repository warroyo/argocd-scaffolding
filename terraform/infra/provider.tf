terraform {
  # optional() object defaults in the modules need >= 1.3; the repo is developed
  # against 1.9+.
  required_version = ">= 1.9"
  required_providers {
    vcfa = {
      source  = "vmware/vcfa"
      version = "~> 1.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
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

data "vcfa_kubeconfig" "org" {}

provider "kubernetes" {
  alias    = "vcfa-org"
  host     = data.vcfa_kubeconfig.org.host
  insecure = data.vcfa_kubeconfig.org.insecure_skip_tls_verify
  token    = data.vcfa_kubeconfig.org.token
}
