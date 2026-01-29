variable "ns_name" {
  type    = string
  default = "sample-ns"
}

variable "argo_namespace" {
  type    = string
  default = "default"
}

variable "argo_project" {
  type    = string
  default = "testing"
}

# New variable for cluster labels
variable "argo_cluster_labels" {
  type        = map(string)
  description = "A map of labels to apply to the clusterLabels field"
  default = {
    test = "test"
  }
}