
include "root" {
  path =  find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}//terraform/tenant"
}

inputs = {
  vcfa_refresh_token = values.vcfa_refresh_token
  vcfa_url           = values.vcfa_url
  vcfa_org           = values.vcfa_org
  region_name        = values.region_name
}

