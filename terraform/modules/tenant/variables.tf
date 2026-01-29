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
    zone_name     = optional(string,"zone1")
    storage_limit = optional(string, "102400Mi")
    class_name    = optional(string, "small")
    mem_limit     = optional(string, "10000Mi")
    cpu_limit     = optional(string, "10000M")
    storage_policy     = optional(string, "vSAN Default Storage Policy")
  }))
  description = "A map of namespaces with associated resource and location settings"
  default     = {}
}