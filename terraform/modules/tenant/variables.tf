variable "region_name" {
  type        = string
}

variable "project_name" {
   type = string
  default = "default-project"
}

variable "namespaces" {
  type = map(object({
    name          = string
    zone_name     = optional(string,"z-wld-a")
    storage_limit = optional(string, "102400Mi")
    class_name    = optional(string, "small")
    mem_limit     = optional(string, "10000Mi")
    cpu_limit     = optional(string, "10000M")
    storage_policy     = optional(string, "vSAN Default Storage Policy")
    deploy_argo   = optional(bool, false)
  }))
  description = "A map of namespaces with associated resource and location settings"
  default     = {}
}
variable "argo_namespace" {
   type = string
}

variable "avi_enabled" {
  type        = bool
  description = "Whether the region uses AVI as its load balancer."
  default     = true
}

variable "vpc_connectivity_profile_name" {
  type        = string
  description = "Name of the VPCConnectivityProfile to attach the tenant VPC to. If unset, the default profile for region_name is looked up via a data source."
  default     = null
}
