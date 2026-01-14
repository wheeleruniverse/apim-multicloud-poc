# Main Terraform Configuration for Development Environment
# This orchestrates the deployment of all multi-cloud resources

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.57"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }

  # Remote state backend - Run scripts/bootstrap-azure.sh first to create these resources
  backend "azurerm" {
    resource_group_name  = "apim-multicloud-poc-dev-tfstate-rg"
    storage_account_name = "steusapimmcpoctfstate"
    container_name       = "tfstate"
    key                  = "apim-multicloud-poc-dev.tfstate"
  }
}

# Azure Provider Configuration
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    api_management {
      purge_soft_delete_on_destroy = true
    }
  }
}

# AWS Provider Configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# Kubernetes Provider for AKS
provider "kubernetes" {
  alias = "aks"

  host                   = module.azure_aks.kube_config_host
  client_certificate     = base64decode(module.azure_aks.client_certificate)
  client_key             = base64decode(module.azure_aks.client_key)
  cluster_ca_certificate = base64decode(module.azure_aks.cluster_ca_certificate)
}

# Kubernetes Provider for EKS
provider "kubernetes" {
  alias = "eks"

  host                   = module.aws_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.aws_eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.aws_eks.cluster_name, "--region", var.aws_region]
  }
}

# Helm Provider for EKS
provider "helm" {
  alias = "eks"

  kubernetes {
    host                   = module.aws_eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.aws_eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.aws_eks.cluster_name, "--region", var.aws_region]
    }
  }
}

# Local values
locals {
  project_name = "apim-multicloud-poc"
  environment  = var.environment

  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
  }

  azure_tags = merge(local.common_tags, {
    Cloud = "Azure"
  })

  aws_tags = merge(local.common_tags, {
    Cloud = "AWS"
  })
}

# =============================================================================
# AZURE RESOURCES
# =============================================================================

# Azure API Management
module "azure_apim" {
  source = "../../modules/azure-apim"

  resource_group_name = "${local.project_name}-${local.environment}-apim-rg"
  location            = var.azure_location
  apim_name           = "${local.project_name}-${local.environment}-apim"
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  apim_sku            = var.apim_sku
  environment         = local.environment

  # Backend URLs - Use placeholder URLs initially
  # After deploying the APIs to clusters, update these to the actual service URLs
  # Azure: http://hello-api.hello-api.svc.cluster.local
  # AWS: http://hello-api.hello-api.svc.cluster.local
  aks_backend_url = "http://backend-placeholder.example.com/azure"
  eks_backend_url = "http://backend-placeholder.example.com/aws"

  tags = local.azure_tags
}

# Azure AKS Cluster
module "azure_aks" {
  source = "../../modules/azure-aks"

  providers = {
    kubernetes = kubernetes.aks
  }

  resource_group_name   = "${local.project_name}-${local.environment}-aks-rg"
  create_resource_group = true
  location              = var.azure_location

  cluster_name = "${local.project_name}-${local.environment}-aks"
  dns_prefix   = "${local.project_name}-${local.environment}"

  node_count         = var.aks_node_count
  vm_size            = var.aks_vm_size
  enable_autoscaling = var.aks_enable_autoscaling
  min_node_count     = var.aks_min_nodes
  max_node_count     = var.aks_max_nodes

  environment   = local.environment
  api_namespace = var.api_namespace

  create_acr = true
  acr_name   = replace("${local.project_name}${local.environment}acr", "-", "")

  tags = local.azure_tags
}

# =============================================================================
# AWS RESOURCES
# =============================================================================

# AWS EKS Cluster with Self-Hosted Gateway
module "aws_eks" {
  source = "../../modules/aws-eks"

  providers = {
    kubernetes = kubernetes.eks
    helm       = helm.eks
  }

  aws_region   = var.aws_region
  cluster_name = "${local.project_name}-${local.environment}-eks"

  kubernetes_version = var.eks_kubernetes_version
  instance_type      = var.eks_instance_type
  min_node_count     = var.eks_min_nodes
  max_node_count     = var.eks_max_nodes
  desired_node_count = var.eks_desired_nodes

  environment       = local.environment
  api_namespace     = var.api_namespace
  gateway_namespace = var.gateway_namespace
  gateway_replicas  = var.gateway_replicas

  # APIM Gateway configuration
  apim_gateway_token   = var.apim_gateway_token
  apim_config_endpoint = "${module.azure_apim.apim_gateway_url}/configuration"

  tags = local.aws_tags
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "azure_apim_gateway_url" {
  description = "Azure APIM Gateway URL"
  value       = module.azure_apim.apim_gateway_url
}

output "azure_apim_portal_url" {
  description = "Azure APIM Developer Portal URL"
  value       = module.azure_apim.apim_portal_url
}

output "azure_aks_get_credentials" {
  description = "Command to get AKS credentials"
  value       = module.azure_aks.get_credentials_command
}

output "aws_eks_update_kubeconfig" {
  description = "Command to update kubeconfig for EKS"
  value       = module.aws_eks.update_kubeconfig_command
}

output "azure_acr_login_server" {
  description = "Azure Container Registry login server"
  value       = module.azure_aks.acr_login_server
}

output "aws_ecr_repository_url" {
  description = "AWS ECR repository URL"
  value       = module.aws_eks.ecr_repository_url
}

output "gateway_token_command" {
  description = "Command to generate APIM gateway token"
  value       = module.azure_apim.gateway_token_command
}

output "test_urls" {
  description = "URLs for testing the APIs"
  value = {
    azure_api_via_apim = "${module.azure_apim.apim_gateway_url}/${module.azure_apim.azure_api_path}/hello"
    aws_api_via_apim   = "${module.azure_apim.apim_gateway_url}/${module.azure_apim.aws_api_path}/hello"
    gateway_lb_command = module.aws_eks.get_gateway_lb_command
  }
}
