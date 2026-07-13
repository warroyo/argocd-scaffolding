# ArgoCD supervisor endpoints for `make destroy-apps` — OUTPUT ONLY, no resources, so a
# normal apply-bootstrap has zero side effects from this file (nothing written to disk).
#
# Teardown ordering problem: the `*-provision` / `*-apps` Applications are created by the
# ApplicationSet controllers at runtime (not helm-owned), so destroying the bootstrap helm
# release removes ArgoCD *and* the appsets at once — the controllers die before they
# cascade-delete those Applications, orphaning them and leaking the VKS workload clusters
# (whose deletion is driven by the Applications' finalizers).
#
# `make destroy-apps` fixes the order: it deletes the ApplicationSets/Applications and waits
# for the finalizers to cascade WHILE ArgoCD is still up, before destroy-bootstrap. To reach
# the vcfa supervisor where ArgoCD runs (not the state-backend cluster, not any ambient
# kubectl context) it reads this output and builds a throwaway kubeconfig per namespace.
# vcfa tokens are short-lived, so destroy-apps runs `apply -refresh-only` first to re-read
# data.vcfa_kubeconfig into state, making the token below fresh at read time.

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
