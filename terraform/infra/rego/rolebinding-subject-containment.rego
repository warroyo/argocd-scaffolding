# tenant-sync-<tenant> holds the built-in `admin` role cluster-wide, and admin
# covers create on roles/rolebindings — so an unfenced tenant repo could bind an
# arbitrary human or a foreign ServiceAccount, laundering self-granted access
# through a machine identity. The gitops path may therefore bind only
# ServiceAccounts from the RoleBinding's own namespace. Human access does not
# come from a tenant repo at all: the platform binds the tenant's VCFA group
# (apps/base/tenant-users, subjects from tenant-vars). Platform syncs
# impersonate a different username, so they are exempt by identity, not by an
# exemption list.
# See docs/DECISIONS.md #22.

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
  msg := sprintf("gitops may only bind ServiceAccounts, not %v %q; human access is granted by the platform from the tenant's VCFA project membership, not from a tenant repo", [subject.kind, subject.name])
}

violation[{"msg": msg}] {
  is_tenant_sync
  subject := input.review.object.subjects[_]
  subject.kind == "ServiceAccount"
  subject_ns := object.get(subject, "namespace", rb_namespace)
  subject_ns != rb_namespace
  msg := sprintf("ServiceAccount %q is in namespace %q; a RoleBinding may only bind ServiceAccounts from its own namespace %q", [subject.name, subject_ns, rb_namespace])
}
