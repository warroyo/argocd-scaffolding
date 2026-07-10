# No defaults here — the tenant module's typed optional() object is the single
# default site; this module always receives concrete values.

variable "region_name" {
  type = string
}

variable "vpc_name" {
  type = string
}

variable "zone_name" {
  type = string
}

variable "name" {
  type = string
}

variable "storage_limit" {
  type = string
}

variable "class_name" {
  type = string
}

variable "cpu_limit" {
  type = string
}

variable "mem_limit" {
  type = string
}

variable "storage_policy" {
  type = string
}

variable "project_name" {
  type = string
}
