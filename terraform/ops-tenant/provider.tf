terraform {
  required_providers {
    # kubernetes = {
    #   source = "hashicorp/kubernetes"
    # }

    vcfa = {
      source = "vmware/vcfa"
    }
     k8sconnect = {
      source = "jmorris0x0/k8sconnect"
      version = "0.3.6"
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




# provider "kubernetes" {
#   alias = "vcfa-ns"
#   host     = data.vcfa_kubeconfig.kubeconfig.host
#   insecure = data.vcfa_kubeconfig.kubeconfig.insecure_skip_tls_verify
#   token    = data.vcfa_kubeconfig.kubeconfig.token
# }
provider "k8sconnect" {} 