locals {
  argo_password = ( 
    length(trimspace(var.password)) > 0
    ? var.password
    : data.k8sconnect_object.admin-password.object.data.password
  )
}


resource "k8sconnect_object" "argo-cd-instance" {
  yaml_body          = yamlencode({
    "apiVersion" = "argocd-service.vsphere.vmware.com/v1alpha1"
    "kind" = "ArgoCD"
    "metadata" = {
      "name" = var.name
      "namespace" = var.namespace
    }
    "spec" = {
      "applicationSet" = {
        "enabled": true
      }
      "version" = "2.14.15+vmware.1-vks.1"
    }
  })
  cluster = var.cluster

}

resource "k8sconnect_wait" "argocd-instance" {
  object_ref = k8sconnect_object.argo-cd-instance.object_ref

  wait_for = {
    field_value   = {
      "status.conditions[2].reason" = "ReconcileSucceeded"
    } 
    timeout = "5m"
  }

  cluster = var.cluster
}

module "namespace-register" {
  source = "../argocd-attach-sv-namespace"
  namespace = var.namespace
  argocd_namespace = var.namespace
  cluster = var.cluster
}

resource "k8sconnect_patch" "update-admin-secret" {
  target = {
    api_version = "v1"
    kind        = "Secret"
    name        = "argocd-secret" 
    namespace   = var.namespace
  }

  patch = jsonencode({
     data = {
        "admin.password" = base64encode(bcrypt(var.password))
        "admin.passwordMtime" = base64encode(timestamp())
      }
  })

  cluster = var.cluster
  depends_on = [ k8sconnect_object.argo-cd-instance ]
}


data "k8sconnect_object" "argocd_service" {
  api_version = "v1"
  kind        = "Service"
  name = "argocd-server"
  namespace = var.namespace

  cluster = var.cluster
  depends_on = [ k8sconnect_wait.argocd-instance ]
}


data "k8sconnect_object" "admin-password" {
  api_version = "v1"
  kind        = "Secret"
  name = "argocd-initial-admin-secret"
  namespace = var.namespace

  cluster = var.cluster
  depends_on = [ k8sconnect_wait.argocd-instance ]
}