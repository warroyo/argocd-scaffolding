# Ingress (networking.k8s.io)
violation[{"msg": msg}] {
  input.review.kind.kind == "Ingress"
  host := input.review.object.spec.rules[_].host
  not suffix_allowed(host)
  msg := sprintf("ingress host %q is not within an allowed dns suffix for this tenant %v", [host, input.parameters.allowedSuffixes])
}

# Gateway API HTTPRoute
violation[{"msg": msg}] {
  input.review.kind.kind == "HTTPRoute"
  host := input.review.object.spec.hostnames[_]
  not suffix_allowed(host)
  msg := sprintf("httproute hostname %q is not within an allowed dns suffix for this tenant %v", [host, input.parameters.allowedSuffixes])
}

# Gateway API Gateway
violation[{"msg": msg}] {
  input.review.kind.kind == "Gateway"
  input.review.kind.group == "gateway.networking.k8s.io"
  host := input.review.object.spec.listeners[_].hostname
  not suffix_allowed(host)
  msg := sprintf("gateway listener hostname %q is not within an allowed dns suffix for this tenant %v", [host, input.parameters.allowedSuffixes])
}

# istio Gateway — hosts may be namespace-qualified ("./foo.com", "*/foo.com"),
# strip anything before the "/" before checking the suffix.
violation[{"msg": msg}] {
  input.review.kind.kind == "Gateway"
  input.review.kind.group == "networking.istio.io"
  raw := input.review.object.spec.servers[_].hosts[_]
  host := istio_host(raw)
  not suffix_allowed(host)
  msg := sprintf("istio gateway host %q is not within an allowed dns suffix for this tenant %v", [raw, input.parameters.allowedSuffixes])
}

istio_host(raw) = host {
  parts := split(raw, "/")
  host := parts[count(parts) - 1]
}

suffix_allowed(host) {
  endswith(host, input.parameters.allowedSuffixes[_])
}
