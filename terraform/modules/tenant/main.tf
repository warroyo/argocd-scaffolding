module "project" {
  source = "../project"
  name =  var.project_name
}
module "vpc" {
   source = "../vpc"
   project_name = var.project_name
   region_name = var.region_name

}

module "svns" {
  for_each = var.namespaces
  source = "../svns"
  zone_name = each.value.zone_name
  region_name = var.region_name
  vpc_name = module.vpc.vpc_name
  name = each.value.name
  storage_limit = each.value.storage_limit
  class_name = each.value.class_name
  mem_limit = each.value.mem_limit
  cpu_limit = each.value.cpu_limit
  project_name = module.project.name
  depends_on = [ module.project ]
  storage_policy = each.value.storage_policy
}
