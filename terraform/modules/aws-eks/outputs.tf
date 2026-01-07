# Outputs for AWS EKS Module

output "cluster_id" {
  description = "ID of the EKS cluster"
  value       = module.eks.cluster_id
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN of the cluster"
  value       = module.eks.cluster_iam_role_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded CA data for the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

output "ecr_repository_url" {
  description = "ECR repository URL for API images"
  value       = aws_ecr_repository.api.repository_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.api.arn
}

output "api_namespace" {
  description = "Kubernetes namespace for the Hello API"
  value       = var.api_namespace
}

output "gateway_namespace" {
  description = "Kubernetes namespace for the APIM gateway"
  value       = var.gateway_namespace
}

output "gateway_service_name" {
  description = "Name of the gateway service"
  value       = kubernetes_service.apim_gateway.metadata[0].name
}

# Command to update kubeconfig
output "update_kubeconfig_command" {
  description = "AWS CLI command to update kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# Command to get gateway load balancer hostname
output "get_gateway_lb_command" {
  description = "kubectl command to get gateway load balancer hostname"
  value       = "kubectl get svc apim-gateway -n ${var.gateway_namespace} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
