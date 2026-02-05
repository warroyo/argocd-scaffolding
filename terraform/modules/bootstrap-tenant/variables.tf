variable "argo_password" {
  type = string
  sensitive = true
  default = ""
}

variable "argo_project" {
  type        = string
  default = "default"
}

variable "supervisor_namespace" {
  type        = string
}
variable "root_app" {
  type        = string
  default     = "https://raw.githubusercontent.com/warroyo/argocd-scaffolding/refs/heads/main/argocd/root/root.yaml"
  description = "The raw URL of the file to pull from Git"
}

variable "deploy_argo" {
  type = bool
  default = false
}
variable "argo_ns" {
  type = string  
}

variable "argo_cluster_labels" {
  
}