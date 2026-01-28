output "server_ip" {
  value = data.k8sconnect_object.argocd_service.object.status.loadBalancer.ingress.0.ip
  
}

output "admin_password" {
  value = local.argo_password
  sensitive = true
}