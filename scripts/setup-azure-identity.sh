#!/bin/bash
################################################################################
# Azure Managed Identity Setup for GitHub Actions OIDC
################################################################################
# This script creates an Azure Managed Identity with Federated Credentials
# for GitHub Actions to authenticate without long-lived credentials.
#
# Prerequisites:
#   - Azure CLI installed and authenticated (az login)
#   - GitHub CLI installed and authenticated (gh auth login) - optional
#   - Contributor access to Azure subscription
#   - Existing tfstate storage account (run bootstrap-azure.sh first)
#
# Usage:
#   ./setup-azure-identity.sh [ENVIRONMENT]
#
# Example:
#   ./setup-azure-identity.sh dev
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="apim-multicloud-poc"
GITHUB_REPO="wheeleruniverse/apim-multicloud-poc"
ENVIRONMENT="${1:-dev}"

# APIM Publisher Details
APIM_PUBLISHER_NAME="wheeleruniverse"

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}Azure Managed Identity Setup for GitHub Actions OIDC${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo "Project: $PROJECT_NAME"
echo "Environment: $ENVIRONMENT"
echo "GitHub Repository: $GITHUB_REPO"
echo ""

# Get Azure subscription details
echo -e "${YELLOW}Retrieving Azure subscription details...${NC}"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

if [ -z "$SUBSCRIPTION_ID" ]; then
    echo -e "${RED}Error: Failed to get subscription ID. Please run 'az login' first.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Subscription: $SUBSCRIPTION_NAME${NC}"
echo -e "${GREEN}✓ Subscription ID: $SUBSCRIPTION_ID${NC}"
echo -e "${GREEN}✓ Tenant ID: $TENANT_ID${NC}"
echo ""

# Naming
IDENTITY_NAME="${PROJECT_NAME}-${ENVIRONMENT}-github-actions"
IDENTITY_RG="${PROJECT_NAME}-${ENVIRONMENT}-identity-rg"
TFSTATE_RG="${PROJECT_NAME}-${ENVIRONMENT}-tfstate-rg"
TFSTATE_STORAGE_ACCOUNT="steusapimmcpoctfstate"
LOCATION="eastus"

# Create resource group for identity if it doesn't exist
echo -e "${YELLOW}Ensuring resource group exists for managed identity...${NC}"
if az group show --name "$IDENTITY_RG" &>/dev/null; then
    echo -e "${GREEN}✓ Resource group $IDENTITY_RG already exists${NC}"
else
    echo "Creating resource group $IDENTITY_RG..."
    az group create --name "$IDENTITY_RG" --location "$LOCATION" --output none
    echo -e "${GREEN}✓ Resource group created${NC}"
fi
echo ""

# Create managed identity if it doesn't exist
echo -e "${YELLOW}Creating managed identity...${NC}"
if az identity show --name "$IDENTITY_NAME" --resource-group "$IDENTITY_RG" &>/dev/null; then
    echo -e "${GREEN}✓ Managed identity $IDENTITY_NAME already exists${NC}"
else
    echo "Creating managed identity $IDENTITY_NAME..."
    az identity create \
        --name "$IDENTITY_NAME" \
        --resource-group "$IDENTITY_RG" \
        --location "$LOCATION" \
        --output none
    echo -e "${GREEN}✓ Managed identity created${NC}"

    # Wait a moment for the identity to be fully provisioned
    echo "Waiting for identity to be fully provisioned..."
    sleep 10
fi
echo ""

# Get identity details
echo -e "${YELLOW}Retrieving managed identity details...${NC}"
CLIENT_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$IDENTITY_RG" --query clientId -o tsv)
PRINCIPAL_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$IDENTITY_RG" --query principalId -o tsv)

if [ -z "$CLIENT_ID" ] || [ -z "$PRINCIPAL_ID" ]; then
    echo -e "${RED}Error: Failed to retrieve identity details${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Client ID: $CLIENT_ID${NC}"
echo -e "${GREEN}✓ Principal ID: $PRINCIPAL_ID${NC}"
echo ""

# Create federated credentials for GitHub Actions
echo -e "${YELLOW}Configuring federated credentials for GitHub OIDC...${NC}"

# Federated credential for main branch
MAIN_CRED_NAME="github-actions-main"
MAIN_SUBJECT="repo:${GITHUB_REPO}:ref:refs/heads/main"

if az identity federated-credential show \
    --name "$MAIN_CRED_NAME" \
    --identity-name "$IDENTITY_NAME" \
    --resource-group "$IDENTITY_RG" &>/dev/null; then
    echo -e "${GREEN}✓ Federated credential for main branch already exists${NC}"
else
    echo "Creating federated credential for main branch..."
    az identity federated-credential create \
        --name "$MAIN_CRED_NAME" \
        --identity-name "$IDENTITY_NAME" \
        --resource-group "$IDENTITY_RG" \
        --issuer "https://token.actions.githubusercontent.com" \
        --subject "$MAIN_SUBJECT" \
        --audiences "api://AzureADTokenExchange" \
        --output none
    echo -e "${GREEN}✓ Federated credential created for main branch${NC}"
fi

# Federated credential for environment deployments
ENV_CRED_NAME="github-actions-environment-${ENVIRONMENT}"
ENV_SUBJECT="repo:${GITHUB_REPO}:environment:${ENVIRONMENT}"

if az identity federated-credential show \
    --name "$ENV_CRED_NAME" \
    --identity-name "$IDENTITY_NAME" \
    --resource-group "$IDENTITY_RG" &>/dev/null; then
    echo -e "${GREEN}✓ Federated credential for environment already exists${NC}"
else
    echo "Creating federated credential for environment deployments..."
    az identity federated-credential create \
        --name "$ENV_CRED_NAME" \
        --identity-name "$IDENTITY_NAME" \
        --resource-group "$IDENTITY_RG" \
        --issuer "https://token.actions.githubusercontent.com" \
        --subject "$ENV_SUBJECT" \
        --audiences "api://AzureADTokenExchange" \
        --output none
    echo -e "${GREEN}✓ Federated credential created for environment${NC}"
fi

# Federated credential for pull requests
PR_CRED_NAME="github-actions-pull-request"
PR_SUBJECT="repo:${GITHUB_REPO}:pull_request"

if az identity federated-credential show \
    --name "$PR_CRED_NAME" \
    --identity-name "$IDENTITY_NAME" \
    --resource-group "$IDENTITY_RG" &>/dev/null; then
    echo -e "${GREEN}✓ Federated credential for pull requests already exists${NC}"
else
    echo "Creating federated credential for pull requests..."
    az identity federated-credential create \
        --name "$PR_CRED_NAME" \
        --identity-name "$IDENTITY_NAME" \
        --resource-group "$IDENTITY_RG" \
        --issuer "https://token.actions.githubusercontent.com" \
        --subject "$PR_SUBJECT" \
        --audiences "api://AzureADTokenExchange" \
        --output none
    echo -e "${GREEN}✓ Federated credential created for pull requests${NC}"
fi
echo ""

# Assign Contributor role on subscription
echo -e "${YELLOW}Assigning RBAC roles...${NC}"
echo "Checking Contributor role on subscription..."

# Check if role assignment already exists
if az role assignment list \
    --assignee "$PRINCIPAL_ID" \
    --role "Contributor" \
    --scope "/subscriptions/$SUBSCRIPTION_ID" \
    --query "[?principalId=='$PRINCIPAL_ID'] | length(@)" -o tsv | grep -q "1"; then
    echo -e "${GREEN}✓ Contributor role already assigned on subscription${NC}"
else
    echo "Assigning Contributor role on subscription..."
    az role assignment create \
        --assignee-object-id "$PRINCIPAL_ID" \
        --assignee-principal-type ServicePrincipal \
        --role "Contributor" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" \
        --output none
    echo -e "${GREEN}✓ Contributor role assigned${NC}"
fi

# Assign Storage Blob Data Contributor role on tfstate storage account
echo "Checking Storage Blob Data Contributor role on tfstate storage account..."

# Get storage account resource ID
STORAGE_ACCOUNT_ID=$(az storage account show \
    --name "$TFSTATE_STORAGE_ACCOUNT" \
    --resource-group "$TFSTATE_RG" \
    --query id -o tsv 2>/dev/null || echo "")

if [ -z "$STORAGE_ACCOUNT_ID" ]; then
    echo -e "${YELLOW}⚠ Warning: Terraform state storage account not found${NC}"
    echo -e "${YELLOW}  Please run ./scripts/bootstrap-azure.sh first${NC}"
    echo -e "${YELLOW}  Skipping Storage Blob Data Contributor role assignment${NC}"
else
    # Check if role assignment already exists
    if az role assignment list \
        --assignee "$PRINCIPAL_ID" \
        --role "Storage Blob Data Contributor" \
        --scope "$STORAGE_ACCOUNT_ID" \
        --query "[?principalId=='$PRINCIPAL_ID'] | length(@)" -o tsv | grep -q "1"; then
        echo -e "${GREEN}✓ Storage Blob Data Contributor role already assigned${NC}"
    else
        echo "Assigning Storage Blob Data Contributor role on storage account..."
        az role assignment create \
            --assignee-object-id "$PRINCIPAL_ID" \
            --assignee-principal-type ServicePrincipal \
            --role "Storage Blob Data Contributor" \
            --scope "$STORAGE_ACCOUNT_ID" \
            --output none
        echo -e "${GREEN}✓ Storage Blob Data Contributor role assigned${NC}"
    fi
fi
echo ""

# Summary and next steps
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}Azure Managed Identity Setup Complete!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""

# Check if gh CLI is available
if command -v gh &> /dev/null; then
    echo -e "${YELLOW}GitHub CLI detected! Would you like to automatically configure secrets and variables? (y/n)${NC}"
    read -r CONFIGURE_GH

    if [ "$CONFIGURE_GH" = "y" ] || [ "$CONFIGURE_GH" = "Y" ]; then
        echo ""
        echo -e "${YELLOW}Configuring GitHub secrets...${NC}"

        # Set secrets using gh CLI
        echo "$CLIENT_ID" | gh secret set AZURE_CLIENT_ID --repo "$GITHUB_REPO"
        echo -e "${GREEN}✓ Set AZURE_CLIENT_ID${NC}"

        echo "$TENANT_ID" | gh secret set AZURE_TENANT_ID --repo "$GITHUB_REPO"
        echo -e "${GREEN}✓ Set AZURE_TENANT_ID${NC}"

        echo "$SUBSCRIPTION_ID" | gh secret set AZURE_SUBSCRIPTION_ID --repo "$GITHUB_REPO"
        echo -e "${GREEN}✓ Set AZURE_SUBSCRIPTION_ID${NC}"

        echo ""
        echo -e "${YELLOW}Configuring GitHub variables...${NC}"

        # Set publisher name (hard-coded)
        gh variable set APIM_PUBLISHER_NAME --body "$APIM_PUBLISHER_NAME" --repo "$GITHUB_REPO"
        echo -e "${GREEN}✓ Set APIM_PUBLISHER_NAME = $APIM_PUBLISHER_NAME${NC}"

        # Prompt for email (not hard-coded for privacy)
        echo ""
        echo -e "${BLUE}Enter APIM Publisher Email:${NC}"
        read -r APIM_PUBLISHER_EMAIL

        gh variable set APIM_PUBLISHER_EMAIL --body "$APIM_PUBLISHER_EMAIL" --repo "$GITHUB_REPO"
        echo -e "${GREEN}✓ Set APIM_PUBLISHER_EMAIL${NC}"

        echo ""
        echo -e "${GREEN}✓ All GitHub secrets and variables configured!${NC}"
        echo ""
        echo -e "${BLUE}------------------------------------------------------------${NC}"
        echo -e "${BLUE}Next Steps${NC}"
        echo -e "${BLUE}------------------------------------------------------------${NC}"
        echo ""
        echo "1. Run the AWS setup script:"
        echo "   ./scripts/setup-aws-identity.sh $ENVIRONMENT"
        echo ""
        echo "2. Push the GitHub Actions workflow files (if not already done)"
        echo ""
        echo "3. Run the Azure deployment workflow from GitHub Actions"
        echo ""
    else
        # Manual configuration instructions
        echo -e "${BLUE}GitHub Actions Secrets Configuration${NC}"
        echo -e "${BLUE}------------------------------------------------------------${NC}"
        echo ""
        echo "Add these secrets to your GitHub repository:"
        echo "https://github.com/${GITHUB_REPO}/settings/secrets/actions"
        echo ""
        echo -e "${YELLOW}Repository Secrets (click 'New repository secret'):${NC}"
        echo ""
        echo "Secret Name: AZURE_CLIENT_ID"
        echo "Value: $CLIENT_ID"
        echo ""
        echo "Secret Name: AZURE_TENANT_ID"
        echo "Value: $TENANT_ID"
        echo ""
        echo "Secret Name: AZURE_SUBSCRIPTION_ID"
        echo "Value: $SUBSCRIPTION_ID"
        echo ""
        echo -e "${BLUE}------------------------------------------------------------${NC}"
        echo ""
        echo "Add these variables to your GitHub repository:"
        echo "https://github.com/${GITHUB_REPO}/settings/variables/actions"
        echo ""
        echo -e "${YELLOW}Repository Variables (click 'New repository variable'):${NC}"
        echo ""
        echo "Variable Name: APIM_PUBLISHER_NAME"
        echo "Value: $APIM_PUBLISHER_NAME"
        echo ""
        echo "Variable Name: APIM_PUBLISHER_EMAIL"
        echo "Value: <your-email@example.com>"
        echo ""
        echo -e "${BLUE}------------------------------------------------------------${NC}"
        echo -e "${BLUE}Next Steps${NC}"
        echo -e "${BLUE}------------------------------------------------------------${NC}"
        echo ""
        echo "1. Add the secrets and variables above to your GitHub repository"
        echo ""
        echo "2. Run the AWS setup script:"
        echo "   ./scripts/setup-aws-identity.sh $ENVIRONMENT"
        echo ""
        echo "3. Push GitHub Actions workflow files (if not already done)"
        echo ""
        echo "4. Run the Azure deployment workflow from GitHub Actions"
        echo ""
    fi
else
    # No gh CLI - manual configuration instructions
    echo -e "${YELLOW}GitHub CLI not found. Install it with: brew install gh${NC}"
    echo ""
    echo -e "${BLUE}GitHub Actions Secrets Configuration${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo ""
    echo "Add these secrets to your GitHub repository:"
    echo "https://github.com/${GITHUB_REPO}/settings/secrets/actions"
    echo ""
    echo -e "${YELLOW}Repository Secrets (click 'New repository secret'):${NC}"
    echo ""
    echo "Secret Name: AZURE_CLIENT_ID"
    echo "Value: $CLIENT_ID"
    echo ""
    echo "Secret Name: AZURE_TENANT_ID"
    echo "Value: $TENANT_ID"
    echo ""
    echo "Secret Name: AZURE_SUBSCRIPTION_ID"
    echo "Value: $SUBSCRIPTION_ID"
    echo ""
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo ""
    echo "Add these variables to your GitHub repository:"
    echo "https://github.com/${GITHUB_REPO}/settings/variables/actions"
    echo ""
    echo -e "${YELLOW}Repository Variables (click 'New repository variable'):${NC}"
    echo ""
    echo "Variable Name: APIM_PUBLISHER_NAME"
    echo "Value: $APIM_PUBLISHER_NAME"
    echo ""
    echo "Variable Name: APIM_PUBLISHER_EMAIL"
    echo "Value: <your-email@example.com>"
    echo ""
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${BLUE}Next Steps${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo ""
    echo "1. Add the secrets and variables above to your GitHub repository"
    echo ""
    echo "2. Run the AWS setup script:"
    echo "   ./scripts/setup-aws-identity.sh $ENVIRONMENT"
    echo ""
    echo "3. Push GitHub Actions workflow files (if not already done)"
    echo ""
    echo "4. Run the Azure deployment workflow from GitHub Actions"
    echo ""
fi

echo -e "${GREEN}Done!${NC}"
