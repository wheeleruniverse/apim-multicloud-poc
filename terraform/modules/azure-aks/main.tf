# Azure Kubernetes Service Module
# This module creates an AKS cluster to host the Azure-side Hello API

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
  }
}

# Resource Group (can use existing from APIM or create new)
resource "azurerm_resource_group" "aks" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

locals {
  resource_group_name = var.create_resource_group ? azurerm_resource_group.aks[0].name : var.resource_group_name
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "aks" {
  name                = "${var.cluster_name}-logs"
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = local.resource_group_name
  dns_prefix          = var.dns_prefix

  default_node_pool {
    name                = "default"
    node_count          = var.node_count
    vm_size             = var.vm_size
    enable_auto_scaling = var.enable_autoscaling
    min_count           = var.enable_autoscaling ? var.min_node_count : null
    max_count           = var.enable_autoscaling ? var.max_node_count : null
    
    # Use ephemeral OS disk for better performance
    os_disk_type    = "Ephemeral"
    os_disk_size_gb = 50
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id
  }

  azure_policy_enabled = true

  tags = var.tags
}

# Container Registry for storing API images
resource "azurerm_container_registry" "acr" {
  count               = var.create_acr ? 1 : 0
  name                = var.acr_name
  resource_group_name = local.resource_group_name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = true
  tags                = var.tags
}

# Grant AKS pull access to ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  count                            = var.create_acr ? 1 : 0
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr[0].id
  skip_service_principal_aad_check = true
}

# Kubernetes namespace for the Hello API
resource "kubernetes_namespace" "hello_api" {
  depends_on = [azurerm_kubernetes_cluster.main]
  
  metadata {
    name = var.api_namespace
    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }
}

# ConfigMap for API configuration
resource "kubernetes_config_map" "api_config" {
  depends_on = [kubernetes_namespace.hello_api]
  
  metadata {
    name      = "hello-api-config"
    namespace = var.api_namespace
  }

  data = {
    CLOUD_PROVIDER = "Azure"
    REGION         = var.location
    ENVIRONMENT    = var.environment
  }
}
