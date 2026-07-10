terraform {
  required_version = ">= 1.9"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
    vcfa = {
      source  = "vmware/vcfa"
      version = "~> 1.0"
    }
  }
}
