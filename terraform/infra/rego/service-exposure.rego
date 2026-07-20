# Deny raw NodePort in tenant namespaces. LoadBalancers intentionally not policed
# here — see docs/DECISIONS.md #11.
violation[{"msg": msg}] {
  input.review.object.spec.type == "NodePort"
  input.parameters.denyNodePort
  msg := sprintf("service %q of type NodePort is not permitted; expose via a Gateway-backed LoadBalancer", [input.review.object.metadata.name])
}
