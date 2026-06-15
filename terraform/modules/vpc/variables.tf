variable "region_name" {
  type        = string
}


variable "project_name" {
  type        = string
}

variable "avi_enabled" {
  type        = bool
  description = "Whether the region uses AVI as its load balancer."
  default     = false
}