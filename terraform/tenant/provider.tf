terraform {
  required_providers {
    vcfa = {
      source = "vmware/vcfa"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
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
  alias = "vcfa-org"
  host     = data.vcfa_kubeconfig.org.host
  insecure = data.vcfa_kubeconfig.org.insecure_skip_tls_verify
  token    = data.vcfa_kubeconfig.org.token
}