output "policy_schema_name" {
  description = "The auto-generated ClusterPolicySchema name a ClusterPolicy must reference to use this template."
  value       = "${var.template_name}:custom-policy"
}
