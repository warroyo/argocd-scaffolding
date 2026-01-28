variable "name" {
  type        = string
}

variable "namespace" {
  type        = string
}

variable "password" {
  type = string
  sensitive = true
  default = ""
}

variable "role_type" {
  type = string  
  default = "ClusterRole"
}

variable "role_name" {
  type = string
  default = "edit"
  
}

variable "cluster" {
  type = any
}