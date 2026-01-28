terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }

    vcfa = {
      source = "vmware/vcfa"
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


# needed becuase providers are not dynamic enough
locals {
  tenant_k8s_providers = {
    "tenant-1" = kubernetes.tenant-1
  }
} 

provider "kubernetes" {
  alias = "ops"
  host     = data.vcfa_kubeconfig.ops-kubeconfig.host
  insecure = data.vcfa_kubeconfig.ops-kubeconfig.insecure_skip_tls_verify
  token    = data.vcfa_kubeconfig.ops-kubeconfig.token
}

provider "kubernetes" {
  alias = "tenant-1"
  host     = data.vcfa_kubeconfig.kubeconfig["tenant-1"].host
  insecure = data.vcfa_kubeconfig.kubeconfig["tenant-1"].insecure_skip_tls_verify
  token    = data.vcfa_kubeconfig.kubeconfig["tenant-1"].token
}

