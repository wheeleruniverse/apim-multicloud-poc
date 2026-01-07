# Azure API Management Module
# This module creates an APIM instance with APIs for both Azure and AWS backends

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
  }
}

# Resource Group
resource "azurerm_resource_group" "apim" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# API Management Instance
resource "azurerm_api_management" "main" {
  name                = var.apim_name
  location            = azurerm_resource_group.apim.location
  resource_group_name = azurerm_resource_group.apim.name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email

  sku_name = var.apim_sku

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# Self-Hosted Gateway for AWS
resource "azurerm_api_management_gateway" "aws_gateway" {
  name              = "aws-self-hosted-gateway"
  api_management_id = azurerm_api_management.main.id
  description       = "Self-hosted gateway deployed to AWS EKS"
  location_data {
    name     = "AWS US East"
    region   = "us-east-1"
  }
}

# Gateway Token for Self-Hosted Gateway Authentication
resource "azurerm_api_management_gateway_api" "aws_gateway_api" {
  gateway_id = azurerm_api_management_gateway.aws_gateway.id
  api_id     = azurerm_api_management_api.aws_hello_api.id
}

# Azure Hello API - Backend in AKS
resource "azurerm_api_management_api" "azure_hello_api" {
  name                  = "azure-hello-api"
  resource_group_name   = azurerm_resource_group.apim.name
  api_management_name   = azurerm_api_management.main.name
  revision              = "1"
  display_name          = "Azure Hello API"
  path                  = "azure-api"
  protocols             = ["https"]
  service_url           = var.aks_backend_url
  subscription_required = false

  import {
    content_format = "openapi+json"
    content_value  = jsonencode({
      openapi = "3.0.1"
      info = {
        title   = "Azure Hello API"
        version = "1.0"
      }
      paths = {
        "/hello" = {
          get = {
            operationId = "getHello"
            summary     = "Get hello message from Azure"
            responses = {
              "200" = {
                description = "Successful response"
                content = {
                  "application/json" = {
                    schema = {
                      type = "object"
                      properties = {
                        message = { type = "string" }
                        source  = { type = "string" }
                        timestamp = { type = "string" }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        "/health" = {
          get = {
            operationId = "healthCheck"
            summary     = "Health check endpoint"
            responses = {
              "200" = {
                description = "Healthy"
              }
            }
          }
        }
      }
    })
  }
}

# AWS Hello API - Backend via Self-Hosted Gateway
resource "azurerm_api_management_api" "aws_hello_api" {
  name                  = "aws-hello-api"
  resource_group_name   = azurerm_resource_group.apim.name
  api_management_name   = azurerm_api_management.main.name
  revision              = "1"
  display_name          = "AWS Hello API"
  path                  = "aws-api"
  protocols             = ["https"]
  service_url           = var.eks_backend_url
  subscription_required = false

  import {
    content_format = "openapi+json"
    content_value  = jsonencode({
      openapi = "3.0.1"
      info = {
        title   = "AWS Hello API"
        version = "1.0"
      }
      paths = {
        "/hello" = {
          get = {
            operationId = "getHello"
            summary     = "Get hello message from AWS"
            responses = {
              "200" = {
                description = "Successful response"
                content = {
                  "application/json" = {
                    schema = {
                      type = "object"
                      properties = {
                        message = { type = "string" }
                        source  = { type = "string" }
                        timestamp = { type = "string" }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        "/health" = {
          get = {
            operationId = "healthCheck"
            summary     = "Health check endpoint"
            responses = {
              "200" = {
                description = "Healthy"
              }
            }
          }
        }
      }
    })
  }
}

# Policy for Azure API - Standard backend routing
resource "azurerm_api_management_api_policy" "azure_api_policy" {
  api_name            = azurerm_api_management_api.azure_hello_api.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.apim.name

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <set-header name="X-Forwarded-For" exists-action="override">
      <value>@(context.Request.IpAddress)</value>
    </set-header>
    <set-header name="X-APIM-Gateway" exists-action="override">
      <value>Azure-Managed</value>
    </set-header>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
    <set-header name="X-Served-By" exists-action="override">
      <value>Azure-APIM</value>
    </set-header>
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
}

# Policy for AWS API - Routes through self-hosted gateway
resource "azurerm_api_management_api_policy" "aws_api_policy" {
  api_name            = azurerm_api_management_api.aws_hello_api.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.apim.name

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <set-header name="X-Forwarded-For" exists-action="override">
      <value>@(context.Request.IpAddress)</value>
    </set-header>
    <set-header name="X-APIM-Gateway" exists-action="override">
      <value>Self-Hosted-AWS</value>
    </set-header>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
    <set-header name="X-Served-By" exists-action="override">
      <value>Self-Hosted-Gateway-AWS</value>
    </set-header>
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
}

# Named Value for storing configuration
resource "azurerm_api_management_named_value" "environment" {
  name                = "environment"
  resource_group_name = azurerm_resource_group.apim.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "environment"
  value               = var.environment
}

# Products
resource "azurerm_api_management_product" "multicloud" {
  product_id            = "multicloud-apis"
  api_management_name   = azurerm_api_management.main.name
  resource_group_name   = azurerm_resource_group.apim.name
  display_name          = "Multi-Cloud APIs"
  description           = "APIs accessible across Azure and AWS"
  subscription_required = false
  approval_required     = false
  published             = true
}

resource "azurerm_api_management_product_api" "azure_product_api" {
  api_name            = azurerm_api_management_api.azure_hello_api.name
  product_id          = azurerm_api_management_product.multicloud.product_id
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.apim.name
}

resource "azurerm_api_management_product_api" "aws_product_api" {
  api_name            = azurerm_api_management_api.aws_hello_api.name
  product_id          = azurerm_api_management_product.multicloud.product_id
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.apim.name
}

# Diagnostic settings for logging
resource "azurerm_api_management_logger" "app_insights" {
  count               = var.application_insights_id != null ? 1 : 0
  name                = "app-insights-logger"
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.apim.name
  resource_id         = var.application_insights_id

  application_insights {
    instrumentation_key = var.application_insights_key
  }
}
