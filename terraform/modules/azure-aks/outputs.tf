# Outputs for Azure AKS Module

output "cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "kube_config" {
  description = "Kubernetes config for the cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "kube_config_host" {
  description = "Kubernetes API server host"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].host
  sensitive   = true
}

output "client_certificate" {
  description = "Client certificate for Kubernetes"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].client_certificate
  sensitive   = true
}

output "client_key" {
  description = "Client key for Kubernetes"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].client_key
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "CA certificate for the cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "kubelet_identity" {
  description = "Kubelet managed identity"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0]
}

output "acr_login_server" {
  description = "ACR login server URL"
  value       = var.create_acr ? azurerm_container_registry.acr[0].login_server : null
}

output "acr_admin_username" {
  description = "ACR admin username"
  value       = var.create_acr ? azurerm_container_registry.acr[0].admin_username : null
  sensitive   = true
}

output "acr_admin_password" {
  description = "ACR admin password"
  value       = var.create_acr ? azurerm_container_registry.acr[0].admin_password : null
  sensitive   = true
}

output "api_namespace" {
  description = "Kubernetes namespace for the API"
  value       = var.api_namespace
}

output "resource_group_name" {
  description = "Resource group name"
  value       = local.resource_group_name
}

# Command to get credentials
output "get_credentials_command" {
  description = "Azure CLI command to get cluster credentials"
  value       = "az aks get-credentials --resource-group ${local.resource_group_name} --name ${azurerm_kubernetes_cluster.main.name} --overwrite-existing"
}
