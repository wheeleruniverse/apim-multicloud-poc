# Variables for Azure API Management Module

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "apim_name" {
  description = "Name of the API Management instance"
  type        = string
}

variable "publisher_name" {
  description = "Publisher name for APIM"
  type        = string
}

variable "publisher_email" {
  description = "Publisher email for APIM"
  type        = string
}

variable "apim_sku" {
  description = "SKU for APIM (Developer, Basic, Standard, Premium)"
  type        = string
  default     = "Developer_1"
  
  validation {
    condition     = can(regex("^(Developer|Basic|Standard|Premium)_[0-9]+$", var.apim_sku))
    error_message = "APIM SKU must be in format SKU_count (e.g., Developer_1, Premium_2)"
  }
}

variable "aks_backend_url" {
  description = "Backend URL for Azure AKS service"
  type        = string
}

variable "eks_backend_url" {
  description = "Backend URL for AWS EKS service (accessed via self-hosted gateway)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "application_insights_id" {
  description = "Application Insights resource ID for logging"
  type        = string
  default     = null
}

variable "application_insights_key" {
  description = "Application Insights instrumentation key"
  type        = string
  default     = null
  sensitive   = true
}
