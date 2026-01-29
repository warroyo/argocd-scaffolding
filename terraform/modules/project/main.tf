resource "kubernetes_manifest" "project" {
  manifest = {
    "apiVersion" = "project.cci.vmware.com/v1alpha2"
    "kind"       = "Project"
    "metadata" = {
      "name" = var.name
    }
    "spec" = {
      "description" = "Project for tenant created by Terraform"
    }
  }
}

resource "time_sleep" "wait_10_seconds" {
  depends_on = [kubernetes_manifest.project]

  create_duration = "10s"
}

output "name" {
  value = var.name
}