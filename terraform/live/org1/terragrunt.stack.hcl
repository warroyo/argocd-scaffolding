stack "main" {
  source = "${get_repo_root()}/terraform/catalog/stacks/main"
  path   = "will-org"

  values = {
      vcfa_refresh_token = get_env("TF_VAR_vcfa_refresh_token", "")
      vcfa_url           = get_env("TF_VAR_vcfa_url", "")
      vcfa_org           = get_env("TF_VAR_vcfa_org", "")
      region_name        = get_env("TF_VAR_region_name", "")
      argo_password      = get_env("TF_VAR_argo_password", "")
      ako_secret_enabled = get_env("TF_VAR_ako_secret_enabled", "false")
      ako_username       = get_env("TF_VAR_ako_username", "")
      ako_password       = get_env("TF_VAR_ako_password", "")
      ako_ca_data        = get_env("TF_VAR_ako_ca_data", "")
  }
}