# Grants each ArgoCD instance's VCFA service account the "ArgoCD Instance" org
# role, which the operator's API path leaves empty (the UI adds it). Without it
# every ManagedEntity fails "No assigned roles". See docs/DECISIONS.md #25.

locals {
  argocd_instance_name = yamldecode(file("${path.module}/../../charts/bootstrap-tenant/values.yaml")).argoInstance.name
}

resource "terraform_data" "argocd_sa_role" {
  for_each = local.argo_namespaces

  # Re-run when the instance lands in a different namespace; the script is idempotent.
  triggers_replace = [each.value.namespace, local.argocd_instance_name]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "${path.module}/../../scripts/grant-argocd-sa-role.sh"
    environment = {
      KUBE_HOST          = data.vcfa_kubeconfig.ns[each.key].host
      KUBE_TOKEN         = data.vcfa_kubeconfig.ns[each.key].token
      KUBE_INSECURE      = tostring(data.vcfa_kubeconfig.ns[each.key].insecure_skip_tls_verify)
      NAMESPACE          = each.value.namespace
      ARGOCD_NAME        = local.argocd_instance_name
      VCFA_URL           = var.vcfa_url
      VCFA_ORG           = var.vcfa_org
      VCFA_REFRESH_TOKEN = var.vcfa_refresh_token
    }
  }
}
