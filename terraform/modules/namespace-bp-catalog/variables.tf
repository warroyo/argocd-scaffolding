variable "project_id" {
  type        = string
}

variable "enabled_projects" {
  type = list(string)
  default = [  ]
}

variable "api_token" {
  type = string
  sensitive = true
}

variable "vcfa_url" {
  type        = string
}
variable "org" {
  type        = string
}
