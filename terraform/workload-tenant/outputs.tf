
output "argo_ips" {
  description = "A map of IPs  for each Argo CD instance."
  
  value = {
    for key, instance in module.argocd-instance : key => instance.server_ip
  }
  
}


output "argo_passwords" {
  description = "A map of admin passwords for each Argo CD instance."
  
  value = {
    for key, instance in module.argocd-instance : key => instance.admin_password
  }
  
  sensitive = true
}