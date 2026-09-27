terraform {
  required_version = ">= 1.11" # write-only arguments (argocd-sa-role.tf)
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
    vcfa = {
      source  = "vmware/vcfa"
      version = "~> 1.0"
    }
    terracurl = {
      source  = "devops-rob/terracurl"
      version = "~> 2.11"
    }
  }
}
