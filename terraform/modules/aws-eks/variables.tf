# Variables for AWS EKS Module

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.28"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnets" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnets" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "min_node_count" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 5
}

variable "desired_node_count" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

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

variable "gateway_replicas" {
  description = "Number of self-hosted gateway replicas"
  type        = number
  default     = 2
}

variable "apim_gateway_token" {
  description = "Authentication token for the APIM self-hosted gateway"
  type        = string
  sensitive   = true
}

variable "apim_config_endpoint" {
  description = "Configuration endpoint URL for APIM self-hosted gateway"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
