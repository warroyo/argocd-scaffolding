# Issuer + CA for components/oidc-auth, derived from var.vcfa_url (audience is
# var.vcfa_oidc_audience). Design: docs/ARCHITECTURE.md "VCFA identity", DECISIONS #21.

locals {
  # Host from var.vcfa_url regardless of scheme/path (e.g. https://host/api).
  vcfa_host   = regex("^(?:https?://)?([^/]+)", var.vcfa_url)[0]
  oidc_issuer = "https://${local.vcfa_host}/oidc"

  # CA bundle = the CA certs the VCFA endpoint presents (intermediates + root,
  # excluding the leaf). Fall back to the full chain if none are flagged is_ca
  # (a self-signed leaf that is its own CA). PEM, not base64.
  _oidc_ca_certs = [for c in data.tls_certificate.vcfa.certificates : c.cert_pem if c.is_ca]
  oidc_ca_pem = trimspace(join("", length(local._oidc_ca_certs) > 0
    ? local._oidc_ca_certs
  : [for c in data.tls_certificate.vcfa.certificates : c.cert_pem]))
}

# Probes the VCFA TLS endpoint for its cert chain (no auth, non-secret).
data "tls_certificate" "vcfa" {
  url = "https://${local.vcfa_host}"
}
