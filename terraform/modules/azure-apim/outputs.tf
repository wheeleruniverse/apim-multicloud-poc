# Outputs for Azure API Management Module

output "apim_id" {
  description = "ID of the API Management instance"
  value       = azurerm_api_management.main.id
}

output "apim_name" {
  description = "Name of the API Management instance"
  value       = azurerm_api_management.main.name
}

output "apim_gateway_url" {
  description = "Gateway URL of the API Management instance"
  value       = azurerm_api_management.main.gateway_url
}

output "apim_management_api_url" {
  description = "Management API URL"
  value       = azurerm_api_management.main.management_api_url
}

output "apim_portal_url" {
  description = "Developer portal URL"
  value       = azurerm_api_management.main.developer_portal_url
}

output "apim_public_ip_addresses" {
  description = "Public IP addresses of APIM"
  value       = azurerm_api_management.main.public_ip_addresses
}

output "self_hosted_gateway_id" {
  description = "ID of the self-hosted gateway"
  value       = azurerm_api_management_gateway.aws_gateway.id
}

output "self_hosted_gateway_name" {
  description = "Name of the self-hosted gateway"
  value       = azurerm_api_management_gateway.aws_gateway.name
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.apim.name
}

output "azure_api_path" {
  description = "Path for Azure Hello API"
  value       = azurerm_api_management_api.azure_hello_api.path
}

output "aws_api_path" {
  description = "Path for AWS Hello API"
  value       = azurerm_api_management_api.aws_hello_api.path
}

# Output for generating self-hosted gateway token
output "gateway_token_command" {
  description = "Azure CLI command to generate gateway token"
  value       = "az apim gateway token create --gateway-id ${azurerm_api_management_gateway.aws_gateway.name} --resource-group ${azurerm_resource_group.apim.name} --service-name ${azurerm_api_management.main.name} --expiry '2025-12-31T23:59:59Z'"
}
