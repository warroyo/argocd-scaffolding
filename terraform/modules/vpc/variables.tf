variable "region_name" {
  type = string
}


variable "project_name" {
  type = string
}

variable "avi_enabled" {
  type        = bool
  description = "Whether the region uses AVI as its load balancer."
  default     = false
}

variable "vpc_connectivity_profile_name" {
  type        = string
  description = "Name of the VPCConnectivityProfile to attach the VPC to. If unset, the default profile for region_name is looked up via the kubernetes_resources data source."
  default     = null
}

variable "private_cidr" {
  type        = string
  description = "Private CIDR for the VPC. null keeps the historical default (every tenant VPC gets the same CIDR — fine for NATed VPCs, override if routed)."
  default     = null
}