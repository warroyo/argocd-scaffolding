resource "local_file" "tenant_vars" {
  for_each = local.tenant_map

  content = templatefile("${path.module}/../../templates/tenant/vars.tftpl", {
    tenant_uuid = module.tenant[each.key].project_id
    vpc_name    = "${each.key}-${var.region_name}-vpc"
  })
  filename        = "${path.module}/../../infrastructure/clusters/${each.key}/vars/tenant-vars.yaml"
  file_permission = "0644"
}

resource "local_file" "namespace_details" {
  for_each = local.ns_deployments

  content = templatefile("${path.module}/../../templates/tenant/namespace-details.tftpl", {
    namespace      = each.value.ns_name
    argo_namespace = each.value.argo_namespace
    tenant         = each.value.tenant_name
  })
  filename        = "${path.module}/../../infrastructure/clusters/${each.value.tenant_name}/${each.value.ns_name}/namespace-details.yaml"
  file_permission = "0644"
}
