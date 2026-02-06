stack "tenant-management" {
  source = "${find_in_parent_folders("catalog/stacks")}/tenant-management"
  path   = "tenant-management"

  values = {
      vcfa_refresh_token = get_env("TF_VAR_vcfa_refresh_token", "")
      vcfa_url           = get_env("TF_VAR_vcfa_url", "")
      vcfa_org           = get_env("TF_VAR_vcfa_org", "")
      region_name        = get_env("TF_VAR_region_name", "")
      argo_password      = get_env("TF_VAR_argo_password", "")
  }
}