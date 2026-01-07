# AWS EKS Module with APIM Self-Hosted Gateway
# This module creates an EKS cluster with the self-hosted gateway and Hello API

terraform {
  required_providers {
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
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# VPC for EKS
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = var.environment != "prod"
  enable_dns_hostnames   = true
  enable_dns_support     = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = 1
  }

  tags = var.tags
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    main = {
      name           = "main-node-group"
      instance_types = [var.instance_type]
      
      min_size     = var.min_node_count
      max_size     = var.max_node_count
      desired_size = var.desired_node_count

      labels = {
        Environment = var.environment
        NodeGroup   = "main"
      }
    }
  }

  # Cluster add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  tags = var.tags
}

# ECR Repository for API images
resource "aws_ecr_repository" "api" {
  name                 = "${var.cluster_name}-hello-api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

# ECR Lifecycle policy
resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Kubernetes namespace for Hello API
resource "kubernetes_namespace" "hello_api" {
  depends_on = [module.eks]
  
  metadata {
    name = var.api_namespace
    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }
}

# Kubernetes namespace for APIM Self-Hosted Gateway
resource "kubernetes_namespace" "apim_gateway" {
  depends_on = [module.eks]
  
  metadata {
    name = var.gateway_namespace
    labels = {
      environment = var.environment
      managed-by  = "terraform"
      component   = "apim-self-hosted-gateway"
    }
  }
}

# Secret for APIM Gateway Token
resource "kubernetes_secret" "gateway_token" {
  depends_on = [kubernetes_namespace.apim_gateway]
  
  metadata {
    name      = "apim-gateway-token"
    namespace = var.gateway_namespace
  }

  data = {
    gateway-token = var.apim_gateway_token
  }

  type = "Opaque"
}

# ConfigMap for API configuration
resource "kubernetes_config_map" "api_config" {
  depends_on = [kubernetes_namespace.hello_api]
  
  metadata {
    name      = "hello-api-config"
    namespace = var.api_namespace
  }

  data = {
    CLOUD_PROVIDER = "AWS"
    REGION         = var.aws_region
    ENVIRONMENT    = var.environment
  }
}

# ConfigMap for Self-Hosted Gateway configuration
resource "kubernetes_config_map" "gateway_config" {
  depends_on = [kubernetes_namespace.apim_gateway]
  
  metadata {
    name      = "apim-gateway-config"
    namespace = var.gateway_namespace
  }

  data = {
    # Configuration backup settings for resilience
    "config.service.auth"          = "GatewayKey ${var.apim_gateway_token}"
    "config.service.endpoint"      = var.apim_config_endpoint
    "config.service.syncInterval"  = "60"
    "config.service.backupEnabled" = "true"
    "config.service.backupPath"    = "/apim/config-backup"
    
    # Telemetry settings
    "telemetry.metrics.cloud" = "AWS"
    "telemetry.logs.std"      = "text"
  }
}

# PersistentVolumeClaim for configuration backup
resource "kubernetes_persistent_volume_claim" "gateway_config_backup" {
  depends_on = [kubernetes_namespace.apim_gateway]
  
  metadata {
    name      = "gateway-config-backup"
    namespace = var.gateway_namespace
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
    storage_class_name = "gp2"
  }
}

# APIM Self-Hosted Gateway Deployment
resource "kubernetes_deployment" "apim_gateway" {
  depends_on = [
    kubernetes_namespace.apim_gateway,
    kubernetes_secret.gateway_token,
    kubernetes_config_map.gateway_config,
    kubernetes_persistent_volume_claim.gateway_config_backup
  ]
  
  metadata {
    name      = "apim-self-hosted-gateway"
    namespace = var.gateway_namespace
    labels = {
      app = "apim-gateway"
    }
  }

  spec {
    replicas = var.gateway_replicas

    selector {
      match_labels = {
        app = "apim-gateway"
      }
    }

    template {
      metadata {
        labels = {
          app = "apim-gateway"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "4290"
        }
      }

      spec {
        container {
          name  = "apim-gateway"
          image = "mcr.microsoft.com/azure-api-management/gateway:v2"

          port {
            container_port = 8080
            name           = "http"
          }
          port {
            container_port = 8081
            name           = "https"
          }
          port {
            container_port = 4290
            name           = "metrics"
          }

          env {
            name = "config.service.auth"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.gateway_token.metadata[0].name
                key  = "gateway-token"
              }
            }
          }

          env {
            name  = "config.service.endpoint"
            value = var.apim_config_endpoint
          }

          # Enable configuration backup for Azure outage resilience
          env {
            name  = "config.service.backupEnabled"
            value = "true"
          }

          env {
            name  = "config.service.backupPath"
            value = "/apim/config-backup"
          }

          # Sync interval in seconds
          env {
            name  = "config.service.syncInterval"
            value = "60"
          }

          # Retry settings for resilience
          env {
            name  = "config.service.maxRetryCount"
            value = "10"
          }

          env {
            name  = "config.service.retryInterval"
            value = "30"
          }

          # Logging
          env {
            name  = "telemetry.logs.std"
            value = "text"
          }

          volume_mount {
            name       = "config-backup"
            mount_path = "/apim/config-backup"
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "512Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/status-0123456789abcdef"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/status-0123456789abcdef"
              port = 8080
            }
            initial_delay_seconds = 15
            period_seconds        = 5
            failure_threshold     = 3
          }
        }

        volume {
          name = "config-backup"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.gateway_config_backup.metadata[0].name
          }
        }
      }
    }
  }
}

# Service for APIM Self-Hosted Gateway
resource "kubernetes_service" "apim_gateway" {
  depends_on = [kubernetes_deployment.apim_gateway]
  
  metadata {
    name      = "apim-gateway"
    namespace = var.gateway_namespace
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"            = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
      "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
    }
  }

  spec {
    type = "LoadBalancer"

    selector = {
      app = "apim-gateway"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 8080
    }

    port {
      name        = "https"
      port        = 443
      target_port = 8081
    }
  }
}

# Internal service for gateway (used by Hello API for local calls)
resource "kubernetes_service" "apim_gateway_internal" {
  depends_on = [kubernetes_deployment.apim_gateway]
  
  metadata {
    name      = "apim-gateway-internal"
    namespace = var.gateway_namespace
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "apim-gateway"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 8080
    }
  }
}
