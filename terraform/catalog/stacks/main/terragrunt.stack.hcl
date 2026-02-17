stack "tenant-management" {
  source = "${find_in_parent_folders("catalog/stacks")}/tenant-management"
  path   = "tenant-management"

  values = {
     vcfa_refresh_token = values.vcfa_refresh_token
      vcfa_url           = values.vcfa_url
      vcfa_org           = values.vcfa_org
      region_name        = values.region_name
      argo_password = values.argo_password
      ako_secret_enabled = values.ako_secret_enabled
      ako_username       = values.ako_username
      ako_password       = values.ako_password
      ako_ca_data        = values.ako_ca_data
  }
}