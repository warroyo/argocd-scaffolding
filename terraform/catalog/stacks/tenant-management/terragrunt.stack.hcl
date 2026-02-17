
locals {
  units_path = find_in_parent_folders("catalog/units")
}
unit "tenants" {
  source = "${local.units_path}/tenants"
  path   = "tenants"
  values = {
      vcfa_refresh_token = values.vcfa_refresh_token
      vcfa_url           = values.vcfa_url
      vcfa_org           = values.vcfa_org
      region_name        = values.region_name
  }
}

unit "bootstrap" {
  source = "${local.units_path}/bootstrap"
  path   = "bootstrap"

  values = {
    tenants_path = "../tenants"
    argo_password = values.argo_password
    ako_secret_enabled = values.ako_secret_enabled
    ako_username       = values.ako_username
    ako_password       = values.ako_password
    ako_ca_data        = values.ako_ca_data
  }
}
