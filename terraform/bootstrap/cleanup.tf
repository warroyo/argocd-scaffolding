# OUTPUT ONLY (no resources) — supervisor endpoints for `make destroy-apps`.
#
# Teardown ordering: the *-provision/*-apps Applications are created by the
# ApplicationSet controllers at runtime, so destroying the bootstrap helm release
# would remove ArgoCD + the appsets together and orphan them — leaking the VKS
# clusters whose deletion rides on the Applications' finalizers. destroy-apps
# deletes the Applications and waits for finalizers WHILE ArgoCD is still up, then
# destroy-bootstrap. It reaches the supervisor via a throwaway per-namespace
# kubeconfig from this output; vcfa tokens are short-lived, so it runs a
# refresh-only plan+apply first to re-read a fresh token (two-step avoids the
# saved-plan "can't set a variable" guard).

locals {
  argo_namespaces = { for k, v in var.namespace_config : k => v if v.deploy_argo }
}

output "argo_endpoints" {
  description = "Per deploy_argo namespace (keyed by suffixed namespace name): vcfa supervisor host + token + namespace, for pre-destroy ArgoCD app cleanup (make destroy-apps)."
  sensitive   = true
  value = {
    for k, v in local.argo_namespaces : v.namespace => {
      host      = data.vcfa_kubeconfig.ns[k].host
      token     = data.vcfa_kubeconfig.ns[k].token
      insecure  = data.vcfa_kubeconfig.ns[k].insecure_skip_tls_verify
      namespace = v.namespace
    }
  }
}
