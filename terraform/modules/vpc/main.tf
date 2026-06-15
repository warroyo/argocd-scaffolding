locals {
  vpc_name = "${var.project_name}-${var.region_name}-vpc"
  vpc_manifest = {
    apiVersion = "vpc.nsx.vmware.com/v1alpha1"
    kind       = "VPC"
    metadata = {
      name = local.vpc_name
    }
    spec = merge(
      {
        description = "tenant vpc for ${var.project_name}"
        privateIPs  = ["192.173.237.0/24"]
        regionName  = var.region_name
      },
      var.avi_enabled ? { loadBalancerVPCEndpoint = { enabled = true } } : {}
    )
  }
  vpc_attach_manifest = {
    apiVersion = "vpc.nsx.vmware.com/v1alpha1"
    kind       = "VPCAttachment"
    metadata = {
      name = "${local.vpc_name}:default"
    }
    spec = {
      regionName                  = var.region_name
      vpcConnectivityProfileName  = "default@${var.region_name}"
      vpcName                     = local.vpc_name
    }
  }
}

resource "kubernetes_manifest" "vpc" {

  manifest = local.vpc_manifest
}

resource "kubernetes_manifest" "vpc-connectivity" {

  manifest = local.vpc_attach_manifest
  depends_on = [ kubernetes_manifest.vpc ]
}




output "vpc_name" {
  value = local.vpc_name
}