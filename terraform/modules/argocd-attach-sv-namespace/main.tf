locals {
  argocd_cluster_config = {
    "bearerToken" = data.k8sconnect_object.argocd-token.object.data.token
    "tlsClientConfig" = {
      "insecure" = true
    }
  }
  argo_namespace = coalesce(var.argocd_namespace, var.namespace)

  
}

resource "k8sconnect_object" "argo-cd-sa" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: ${var.sa_name}
      namespace: ${local.argo_namespace}
  YAML

  cluster = var.cluster

}

resource "k8sconnect_object" "argocd-token" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Secret
    metadata:
      name: ${var.sa_name}-sa-token
      namespace: ${local.argo_namespace}
      annotations:
        kubernetes.io/service-account.name: ${k8sconnect_object.argo-cd-sa.object_ref.name}
    type: kubernetes.io/service-account-token
  YAML
  cluster = var.cluster
}


data "k8sconnect_object" "argocd-token" {
  api_version = k8sconnect_object.argocd-token.object_ref.api_version
  kind        = k8sconnect_object.argocd-token.object_ref.kind
  name        = k8sconnect_object.argocd-token.object_ref.name
  namespace   = k8sconnect_object.argocd-token.object_ref.namespace

  cluster = var.cluster
}


resource "k8sconnect_object" "argo-cd-role-binding" {
  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: RoleBinding
    metadata:
      name: ${var.sa_name}-role-binding
      namespace: ${var.namespace}
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: ${var.role_type}
      name: ${var.role_name}
    subjects:
    - kind: ServiceAccount
      name: ${k8sconnect_object.argo-cd-sa.object_ref.name}
      namespace: ${local.argo_namespace}
  YAML
  cluster = var.cluster
}

resource "k8sconnect_object" "argocd-namespace-register" {
  
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Secret
    metadata:
      name: ${var.namespace}-cluster-secret
      namespace: ${var.argocd_namespace}
      labels:
        argocd.argoproj.io/secret-type: "cluster"
    type: Opaque
    data:
      name: ${base64encode(var.namespace)}
      config: ${sensitive(base64encode(jsonencode(local.argocd_cluster_config)))}
      namespaces: ${base64encode(var.namespace)}
      server: ${base64encode("https://kubernetes.default.svc.cluster.local:443")}
  YAML
  cluster = var.cluster
}
