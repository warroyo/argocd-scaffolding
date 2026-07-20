violation[{"msg": msg}] {
  is_sync_sa
  not project_label_valid
  msg := sprintf("namespace %q must carry label gitops.platform/project=%q", [input.review.object.metadata.name, input.parameters.project])
}

violation[{"msg": msg}] {
  is_sync_sa
  not environment_label_valid
  msg := sprintf("namespace %q must carry label gitops.platform/environment in %v", [input.review.object.metadata.name, input.parameters.allowedEnvironments])
}

# no-adoption: the tenant's sync identity may not add or change the project
# label on a namespace it did not originally create with that label — closes
# off relabeling a pre-existing (possibly platform) namespace as their own.
violation[{"msg": msg}] {
  is_sync_sa
  input.review.operation == "UPDATE"
  old_labels := object.get(input.review.oldObject.metadata, "labels", {})
  object.get(old_labels, "gitops.platform/project", "") != input.parameters.project
  msg := sprintf("namespace %q was not created via this tenant's gitops flow and cannot be adopted", [input.review.object.metadata.name])
}

is_sync_sa {
  input.review.userInfo.username == input.parameters.syncServiceAccounts[_]
}

project_label_valid {
  labels := object.get(input.review.object.metadata, "labels", {})
  object.get(labels, "gitops.platform/project", "") == input.parameters.project
}

environment_label_valid {
  labels := object.get(input.review.object.metadata, "labels", {})
  object.get(labels, "gitops.platform/environment", "") == input.parameters.allowedEnvironments[_]
}
