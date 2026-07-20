# The clusterNamespaceSelector on the ClusterPolicy already restricts
# evaluation to namespaces NOT labeled as this tenant's (gitops.platform/project
# NotIn [<tenant>], which also matches namespaces with no label at all). So any
# write reaching this rule from the tenant's own sync identity is, by
# construction, a write outside namespaces it owns.
violation[{"msg": msg}] {
  input.review.userInfo.username == input.parameters.syncServiceAccounts[_]
  msg := sprintf("gitops deploys are limited to namespaces labeled gitops.platform/project=%q; declare and label the namespace in your repo", [input.parameters.project])
}
