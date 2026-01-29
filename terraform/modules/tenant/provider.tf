terraform {
  required_providers {
    vra = {
      source  = "vmware/vra"
      version = ">= 0.16.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    vcfa = {
      source = "vmware/vcfa"
    }


  }
}

