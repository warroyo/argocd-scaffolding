# tenant-sync-<tenant> holds the built-in `admin` role cluster-wide, and admin
# covers create on roles/rolebindings — so a tenant commit could bind an
# arbitrary human or a foreign ServiceAccount, laundering self-granted access
# through a machine identity. Only same-namespace ServiceAccounts may be bound.
# Platform syncs impersonate a different username, so they are exempt by
# identity, not by an exemption list. Human access arrives through
# apps/base/tenant-users instead. See docs/DECISIONS.md.

is_tenant_sync {
  input.review.userInfo.username == input.parameters.syncServiceAccounts[_]
}

# The RoleBinding's own namespace, which is also a subject's default namespace.
rb_namespace = ns {
  ns := input.review.object.metadata.namespace
  ns != ""
} else = ns {
  ns := object.get(input.review, "namespace", "")
}

violation[{"msg": msg}] {
  is_tenant_sync
  subject := input.review.object.subjects[_]
  subject.kind != "ServiceAccount"
  msg := sprintf("gitops may only bind ServiceAccounts, not %v %q; human access is granted by the platform (apps/base/tenant-users), not from a tenant repo", [subject.kind, subject.name])
}

violation[{"msg": msg}] {
  is_tenant_sync
  subject := input.review.object.subjects[_]
  subject.kind == "ServiceAccount"
  object.get(subject, "namespace", rb_namespace) != rb_namespace
  msg := sprintf("ServiceAccount %q is in namespace %q; a RoleBinding may only bind ServiceAccounts from its own namespace %q", [subject.name, object.get(subject, "namespace", rb_namespace), rb_namespace])
}
