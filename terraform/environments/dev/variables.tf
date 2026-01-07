# Variables for Development Environment

# =============================================================================
# GENERAL VARIABLES
# =============================================================================

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "api_namespace" {
  description = "Kubernetes namespace for the Hello API"
  type        = string
  default     = "hello-api"
}

variable "gateway_namespace" {
  description = "Kubernetes namespace for the APIM self-hosted gateway"
  type        = string
  default     = "apim-gateway"
}

# =============================================================================
# AZURE VARIABLES
# =============================================================================

variable "azure_location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "apim_publisher_name" {
  description = "Publisher name for APIM"
  type        = string
}

variable "apim_publisher_email" {
  description = "Publisher email for APIM"
  type        = string
}

variable "apim_sku" {
  description = "SKU for APIM instance"
  type        = string
  default     = "Developer_1"
}

variable "aks_node_count" {
  description = "Number of AKS nodes"
  type        = number
  default     = 2
}

variable "aks_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_DS2_v2"
}

variable "aks_enable_autoscaling" {
  description = "Enable AKS cluster autoscaling"
  type        = bool
  default     = false
}

variable "aks_min_nodes" {
  description = "Minimum nodes for AKS autoscaling"
  type        = number
  default     = 1
}

variable "aks_max_nodes" {
  description = "Maximum nodes for AKS autoscaling"
  type        = number
  default     = 5
}

# =============================================================================
# AWS VARIABLES
# =============================================================================

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "eks_kubernetes_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.28"
}

variable "eks_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "eks_min_nodes" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 1
}

variable "eks_max_nodes" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 5
}

variable "eks_desired_nodes" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "gateway_replicas" {
  description = "Number of self-hosted gateway replicas"
  type        = number
  default     = 2
}

variable "apim_gateway_token" {
  description = "Authentication token for APIM self-hosted gateway (generate via Azure CLI)"
  type        = string
  sensitive   = true
}
