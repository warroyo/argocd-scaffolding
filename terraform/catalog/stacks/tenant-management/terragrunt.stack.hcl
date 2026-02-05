
unit "tenants" {
  source = "${get_repo_root()}/terraform/catalog/units/tenants"
  path   = "tenants"
  values = {
      vcfa_refresh_token = values.vcfa_refresh_token
      vcfa_url           = values.vcfa_url
      vcfa_org           = values.vcfa_org
      region_name        = values.region_name
  }
}

unit "bootstrap" {
  source = "${get_repo_root()}/terraform/catalog/units/bootstrap"
  path   = "bootstrap"

  values = {
    tenants_path = "${get_repo_root()}/terraform/catalog/units/tenants"
    argo_password = values.argo_password
  }
}
