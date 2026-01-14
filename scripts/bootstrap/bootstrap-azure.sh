#!/bin/bash
################################################################################
# Bootstrap script for Azure APIM Multi-Cloud POC
################################################################################
# This script creates the necessary Azure resources before running Terraform
#
# Usage:
#   ./bootstrap-azure.sh [ENVIRONMENT] [LOCATION]
#
# Example:
#   ./bootstrap-azure.sh dev eastus
################################################################################

set -e  # Exit on error

# Configuration - Hard-coded for this specific project
PROJECT_NAME="apim-multicloud-poc"
ENVIRONMENT="${1:-dev}"
LOCATION="${2:-eastus}"

# Azure naming convention: st + region + project + env + tfstate
# Max 24 chars for storage account name (lowercase letters and numbers only)
STORAGE_ACCOUNT_NAME="steusapimmcpoctfstate"
CONTAINER_NAME="tfstate"
STATE_KEY="apim-multicloud-poc-${ENVIRONMENT}.tfstate"

# Resource group names
STATE_RESOURCE_GROUP="${PROJECT_NAME}-${ENVIRONMENT}-tfstate-rg"

# =============================================================================
# Color output helpers
# =============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# Display Configuration
# =============================================================================

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}Azure Terraform State Backend Bootstrap${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo "Project: $PROJECT_NAME"
echo "Environment: $ENVIRONMENT"
echo "Location: $LOCATION"
echo "Storage Account: $STORAGE_ACCOUNT_NAME"
echo ""

# =============================================================================
# Preflight checks
# =============================================================================

info "Starting Azure bootstrap process..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

info "Using Azure subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"

# =============================================================================
# Create Terraform state resource group
# =============================================================================

info "Creating Terraform state resource group: ${STATE_RESOURCE_GROUP}"

if az group show --name "${STATE_RESOURCE_GROUP}" &> /dev/null; then
    warn "Resource group ${STATE_RESOURCE_GROUP} already exists, skipping..."
else
    az group create \
        --name "${STATE_RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --output none
    success "Created resource group: ${STATE_RESOURCE_GROUP}"
fi

# =============================================================================
# Create storage account for Terraform state
# =============================================================================

info "Creating storage account: ${STORAGE_ACCOUNT_NAME}"

if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${STATE_RESOURCE_GROUP}" &> /dev/null; then
    warn "Storage account ${STORAGE_ACCOUNT_NAME} already exists, skipping..."
else
    az storage account create \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${STATE_RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --encryption-services blob \
        --allow-blob-public-access false \
        --min-tls-version TLS1_2 \
        --output none
    success "Created storage account: ${STORAGE_ACCOUNT_NAME}"
fi

# =============================================================================
# Create blob container for state files
# =============================================================================

info "Creating blob container: ${CONTAINER_NAME}"

if az storage container show \
    --name "${CONTAINER_NAME}" \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --auth-mode login &> /dev/null; then
    warn "Container ${CONTAINER_NAME} already exists, skipping..."
else
    az storage container create \
        --name "${CONTAINER_NAME}" \
        --account-name "${STORAGE_ACCOUNT_NAME}" \
        --auth-mode login \
        --output none
    success "Created container: ${CONTAINER_NAME}"
fi

# Note: Application resource groups (APIM and AKS) will be created by Terraform

# =============================================================================
# Output backend configuration
# =============================================================================

echo ""
success "Bootstrap completed successfully!"
echo ""
echo "======================================================================"
echo "Resource Summary"
echo "======================================================================"
echo ""
echo "Subscription:         ${SUBSCRIPTION_NAME}"
echo "Subscription ID:      ${SUBSCRIPTION_ID}"
echo "Location:             ${LOCATION}"
echo ""
echo "State Resource Group: ${STATE_RESOURCE_GROUP}"
echo "Storage Account:      ${STORAGE_ACCOUNT_NAME}"
echo "Container:            ${CONTAINER_NAME}"
echo "State Key:            ${STATE_KEY}"
echo ""
echo "======================================================================"
echo "Next Steps - Cloud Identity Setup"
echo "======================================================================"
echo ""
echo "1. Setup Azure OIDC for GitHub Actions:"
echo "   ./scripts/bootstrap/setup-azure-identity.sh dev"
echo ""
echo "2. Setup AWS OIDC for GitHub Actions:"
echo "   ./scripts/bootstrap/setup-aws-identity.sh dev us-east-1"
echo ""
echo "3. Commit and push your changes to trigger workflows"
echo ""
echo "4. Deploy via GitHub Actions (not local Terraform):"
echo "   - Go to: https://github.com/wheeleruniverse/apim-multicloud-poc/actions"
echo "   - Run 'Terraform - Azure Deployment' workflow"
echo ""
echo "Note: Application resource groups will be created by GitHub Actions:"
echo "  - apim-multicloud-poc-dev-apim-rg (for APIM)"
echo "  - apim-multicloud-poc-dev-aks-rg (for AKS)"
echo ""
