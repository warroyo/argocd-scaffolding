variable "template_name" {
  type        = string
  description = "Lowercase name for the ClusterPolicyTemplate/ConstraintTemplate. Also used as the Rego package name, so it must match the lowercase of constraint_kind (Gatekeeper requirement)"
}

variable "constraint_kind" {
  type        = string
  description = "The CRD kind Gatekeeper generates for this constraint, PascalCase, its lowercase form must equal template_name"
}

variable "parameters_schema" {
  type        = any
  description = "The openAPIV3Schema.properties object describing the parameters callers can pass in the ClusterPolicy input"
  default     = {}
}

variable "rego_rules" {
  type        = string
  description = "The Gatekeeper Rego violation rule bodies. The module wraps this with the `package <template_name>` header, so only supply the rule bodies"
}

variable "target" {
  type        = string
  description = "The Gatekeeper admission target the rules are enforced against"
  default     = "admission.k8s.gatekeeper.sh"
}
