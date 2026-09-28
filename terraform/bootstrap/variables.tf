variable "vcfa_refresh_token" {
  type        = string
  description = "The VCF Automation refresh token — used to mint per-namespace kubeconfig tokens (vcfa.tf)."
  sensitive   = true
}

variable "vcfa_url" {
  type        = string
  description = "The VCF Automation url"
}

variable "vcfa_org" {
  type        = string
  description = "The VCF Automation org"
}

variable "namespace_config" {
  type = map(object({
    namespace      = string
    tenant_name    = string
    deploy_argo    = bool
    argo_namespace = string
    cluster_labels = map(string)
  }))
  description = "Per-namespace structural config (suffixed names + decision-model labels) — output of the infra run. Passed automatically by the Makefile via TF_VAR_namespace_config."
}

variable "repo_url" {
  type        = string
  description = "URL of the GitOps repo — used as repoURL in the root ArgoCD Application. Empty (the default) reads argocd/repo-config.yaml, the same source the ApplicationSets use, so a fork only edits that one file. Set TF_VAR_repo_url only to deliberately diverge."
  default     = ""
}

variable "argo_password" {
  type        = string
  description = "ArgoCD admin password (bcrypt hash required by chart if used)"
  sensitive   = true
  default     = ""
}
