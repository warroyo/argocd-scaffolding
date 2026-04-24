locals {
  tenants    = yamldecode(file("${path.module}/../../terraform/infra/tenants.yaml")).tenants
  tenant_map = { for t in local.tenants : t.name => t }
}

resource "local_file" "appproject" {
  for_each = local.tenant_map

  content = templatefile("${path.module}/../../templates/tenant/project.tftpl", {
    name = each.key
    type = lookup(each.value, "type", "tenant")
  })
  filename        = "${path.module}/../../argocd/projects/${each.key}.yaml"
  file_permission = "0644"
}

resource "local_file" "projects_kustomization" {
  content = templatefile("${path.module}/../../templates/tenant/kustomization.tftpl", {
    tenants = sort(keys(local.tenant_map))
  })
  filename        = "${path.module}/../../argocd/projects/kustomization.yaml"
  file_permission = "0644"
}

resource "local_file" "vars_kustomization" {
  for_each = local.tenant_map

  content         = <<-EOT
    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization
    resources:
    - tenant-vars.yaml
    EOT
  filename        = "${path.module}/../../infrastructure/clusters/${each.key}/vars/kustomization.yaml"
  file_permission = "0644"
}
