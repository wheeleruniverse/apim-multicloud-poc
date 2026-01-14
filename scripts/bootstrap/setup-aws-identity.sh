#!/bin/bash
################################################################################
# AWS IAM OIDC Identity Provider Setup for GitHub Actions
################################################################################
# This script creates an AWS IAM OIDC Identity Provider and IAM Role
# for GitHub Actions to authenticate without long-lived credentials.
#
# Prerequisites:
#   - AWS CLI installed and authenticated (aws configure or AWS_PROFILE set)
#   - GitHub CLI installed and authenticated (gh auth login) - optional
#   - IAM permissions to create OIDC providers and roles
#   - Account must have permission to attach managed policies
#
# Usage:
#   ./setup-aws-identity.sh [ENVIRONMENT] [AWS_REGION]
#
# Example:
#   ./setup-aws-identity.sh dev us-east-1
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Hard-coded for this specific project
PROJECT_NAME="apim-multicloud-poc"
GITHUB_REPO="wheeleruniverse/apim-multicloud-poc"
ENVIRONMENT="${1:-dev}"
AWS_REGION="${2:-us-east-1}"

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}AWS IAM OIDC Identity Provider Setup for GitHub Actions${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo "Project: $PROJECT_NAME"
echo "Environment: $ENVIRONMENT"
echo "GitHub Repository: $GITHUB_REPO"
echo "AWS Region: $AWS_REGION"
echo ""

# Get AWS account details
echo -e "${YELLOW}Retrieving AWS account details...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text)

if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo -e "${RED}Error: Failed to get AWS account ID. Please configure AWS CLI first.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ AWS Account ID: $AWS_ACCOUNT_ID${NC}"
echo -e "${GREEN}✓ Caller ARN: $CALLER_ARN${NC}"
echo ""

# Confirmation prompt before creating resources
echo -e "${YELLOW}⚠️  This script will create IAM resources in the account above.${NC}"
echo -e "${YELLOW}Would you like to continue? (y/n)${NC}"
read -r CONTINUE

if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
    echo -e "${RED}Aborted by user.${NC}"
    exit 1
fi
echo ""

# Naming
OIDC_PROVIDER_URL="token.actions.githubusercontent.com"
OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_URL}"
ROLE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-github-actions"
ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

# GitHub OIDC thumbprint (official GitHub Actions OIDC thumbprint)
# This is the current thumbprint for GitHub's OIDC provider
GITHUB_OIDC_THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"

# Create OIDC Identity Provider if it doesn't exist
echo -e "${YELLOW}Setting up OIDC Identity Provider...${NC}"

if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" &>/dev/null; then
    echo -e "${GREEN}✓ OIDC Identity Provider already exists${NC}"
else
    echo "Creating OIDC Identity Provider for GitHub Actions..."
    aws iam create-open-id-connect-provider \
        --url "https://${OIDC_PROVIDER_URL}" \
        --client-id-list "sts.amazonaws.com" \
        --thumbprint-list "$GITHUB_OIDC_THUMBPRINT" \
        --tags "Key=Project,Value=${PROJECT_NAME}" "Key=Environment,Value=${ENVIRONMENT}" \
        --output text > /dev/null
    echo -e "${GREEN}✓ OIDC Identity Provider created${NC}"
fi
echo ""

# Create trust policy document
echo -e "${YELLOW}Creating IAM role trust policy...${NC}"

TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER_URL}:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "${OIDC_PROVIDER_URL}:sub": "repo:${GITHUB_REPO}:*"
        }
      }
    }
  ]
}
EOF
)

echo -e "${GREEN}✓ Trust policy created${NC}"
echo ""

# Create IAM role if it doesn't exist
echo -e "${YELLOW}Creating IAM role for GitHub Actions...${NC}"

if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    echo -e "${GREEN}✓ IAM role $ROLE_NAME already exists${NC}"
    echo "Updating assume role policy..."
    aws iam update-assume-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-document "$TRUST_POLICY" \
        --output text > /dev/null
    echo -e "${GREEN}✓ Assume role policy updated${NC}"
else
    echo "Creating IAM role $ROLE_NAME..."
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --description "GitHub Actions OIDC role for ${PROJECT_NAME} ${ENVIRONMENT}" \
        --tags "Key=Project,Value=${PROJECT_NAME}" "Key=Environment,Value=${ENVIRONMENT}" \
        --output text > /dev/null
    echo -e "${GREEN}✓ IAM role created${NC}"
fi
echo ""

# Attach AWS managed policies
echo -e "${YELLOW}Attaching AWS managed policies...${NC}"

MANAGED_POLICIES=(
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
    "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
)

for policy in "${MANAGED_POLICIES[@]}"; do
    policy_name=$(echo "$policy" | awk -F'/' '{print $NF}')
    if aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query "AttachedPolicies[?PolicyArn=='$policy'].PolicyArn" --output text | grep -q "$policy"; then
        echo -e "${GREEN}✓ Policy $policy_name already attached${NC}"
    else
        echo "Attaching policy $policy_name..."
        aws iam attach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn "$policy" \
            --output text > /dev/null
        echo -e "${GREEN}✓ Policy $policy_name attached${NC}"
    fi
done
echo ""

# Create inline policy for additional Terraform permissions
echo -e "${YELLOW}Creating inline policy for Terraform operations...${NC}"

INLINE_POLICY_NAME="${PROJECT_NAME}-${ENVIRONMENT}-terraform-permissions"
INLINE_POLICY=$(cat <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "IAMRoleManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:PassRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListRolePolicies",
        "iam:GetRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:ListInstanceProfilesForRole",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile"
      ],
      "Resource": "*"
    },
    {
      "Sid": "OIDCProviderManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateOpenIDConnectProvider",
        "iam:DeleteOpenIDConnectProvider",
        "iam:GetOpenIDConnectProvider",
        "iam:TagOpenIDConnectProvider",
        "iam:UntagOpenIDConnectProvider",
        "iam:ListOpenIDConnectProviders"
      ],
      "Resource": "*"
    },
    {
      "Sid": "KMSKeyManagement",
      "Effect": "Allow",
      "Action": [
        "kms:CreateKey",
        "kms:CreateAlias",
        "kms:DeleteAlias",
        "kms:DescribeKey",
        "kms:GetKeyPolicy",
        "kms:PutKeyPolicy",
        "kms:ScheduleKeyDeletion",
        "kms:TagResource",
        "kms:UntagResource",
        "kms:EnableKeyRotation",
        "kms:ListAliases",
        "kms:ListKeys"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogsManagement",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy",
        "logs:TagLogGroup",
        "logs:UntagLogGroup",
        "logs:ListTagsLogGroup"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AutoScalingManagement",
      "Effect": "Allow",
      "Action": [
        "autoscaling:CreateAutoScalingGroup",
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:DeleteAutoScalingGroup",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:CreateLaunchConfiguration",
        "autoscaling:DeleteLaunchConfiguration",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:CreateOrUpdateTags",
        "autoscaling:DeleteTags",
        "autoscaling:DescribeTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ElasticLoadBalancingManagement",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2SecurityGroupManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSecurityGroupRules",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:DescribeTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2KeyPairManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateKeyPair",
        "ec2:DeleteKeyPair",
        "ec2:DescribeKeyPairs",
        "ec2:ImportKeyPair"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)

# Check if inline policy exists and create/update it
if aws iam get-role-policy --role-name "$ROLE_NAME" --policy-name "$INLINE_POLICY_NAME" &>/dev/null; then
    echo "Updating inline policy $INLINE_POLICY_NAME..."
    aws iam put-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-name "$INLINE_POLICY_NAME" \
        --policy-document "$INLINE_POLICY" \
        --output text > /dev/null
    echo -e "${GREEN}✓ Inline policy updated${NC}"
else
    echo "Creating inline policy $INLINE_POLICY_NAME..."
    aws iam put-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-name "$INLINE_POLICY_NAME" \
        --policy-document "$INLINE_POLICY" \
        --output text > /dev/null
    echo -e "${GREEN}✓ Inline policy created${NC}"
fi
echo ""

# Summary and next steps
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}AWS IAM OIDC Setup Complete!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""

# Check if gh CLI is available
if command -v gh &> /dev/null; then
    echo -e "${YELLOW}GitHub CLI detected! Would you like to automatically configure the AWS secret? (y/n)${NC}"
    read -r CONFIGURE_GH

    if [ "$CONFIGURE_GH" = "y" ] || [ "$CONFIGURE_GH" = "Y" ]; then
        echo ""
        echo -e "${YELLOW}Configuring GitHub secret...${NC}"

        # Set secret using gh CLI
        echo "$ROLE_ARN" | gh secret set AWS_ROLE_ARN --repo "$GITHUB_REPO"
        echo -e "${GREEN}✓ Set AWS_ROLE_ARN${NC}"

        echo ""
        echo -e "${GREEN}✓ GitHub secret configured!${NC}"
        echo ""
        echo -e "${BLUE}------------------------------------------------------------${NC}"
        echo -e "${BLUE}Next Steps${NC}"
        echo -e "${BLUE}------------------------------------------------------------${NC}"
        echo ""
        echo "1. Ensure Azure secrets and variables are configured (run setup-azure-identity.sh)"
        echo ""
        echo "2. Run the Azure deployment workflow first to create APIM:"
        echo "   - Go to Actions → 'Terraform - Azure Deployment'"
        echo "   - Operation: apply"
        echo "   - Environment: $ENVIRONMENT"
        echo ""
        echo "3. After Azure deployment succeeds, generate the APIM gateway token:"
        echo ""
        echo "   az apim gateway token create \\"
        echo "     --resource-group ${PROJECT_NAME}-${ENVIRONMENT}-apim-rg \\"
        echo "     --service-name ${PROJECT_NAME}-${ENVIRONMENT}-apim \\"
        echo "     --gateway-id aws-self-hosted-gateway \\"
        echo "     --expiry 2026-12-31T23:59:59Z \\"
        echo "     --query value -o tsv"
        echo ""
        echo "4. Add the gateway token to GitHub using gh CLI:"
        echo ""
        echo "   echo '<token-from-step-4>' | gh secret set TF_VAR_apim_gateway_token --repo $GITHUB_REPO"
        echo ""
        echo "5. Run the AWS deployment workflow:"
        echo "   - Go to Actions → 'Terraform - AWS Deployment'"
        echo "   - Operation: apply"
        echo "   - Environment: $ENVIRONMENT"
        echo ""
    else
        # Manual configuration instructions
        echo -e "${BLUE}GitHub Actions Secrets Configuration${NC}"
        echo -e "${BLUE}------------------------------------------------------------${NC}"
        echo ""
        echo "Add this secret to your GitHub repository:"
        echo "https://github.com/${GITHUB_REPO}/settings/secrets/actions"
        echo ""
        echo -e "${YELLOW}Repository Secret (click 'New repository secret'):${NC}"
        echo ""
        echo "Secret Name: AWS_ROLE_ARN"
        echo "Value: $ROLE_ARN"
        echo ""
        echo -e "${BLUE}------------------------------------------------------------${NC}"
        echo -e "${BLUE}Next Steps${NC}"
        echo -e "${BLUE}------------------------------------------------------------${NC}"
        echo ""
        echo "1. Add the AWS_ROLE_ARN secret to your GitHub repository"
        echo ""
        echo "2. Ensure Azure secrets and variables are configured:"
        echo "   - AZURE_CLIENT_ID"
        echo "   - AZURE_TENANT_ID"
        echo "   - AZURE_SUBSCRIPTION_ID"
        echo "   - APIM_PUBLISHER_NAME (variable)"
        echo "   - APIM_PUBLISHER_EMAIL (variable)"
        echo ""
        echo "3. Run the Azure deployment workflow first to create APIM"
        echo ""
        echo "4. After Azure deployment, generate the APIM gateway token:"
        echo "   az apim gateway token create \\"
        echo "     --resource-group ${PROJECT_NAME}-${ENVIRONMENT}-apim-rg \\"
        echo "     --service-name ${PROJECT_NAME}-${ENVIRONMENT}-apim \\"
        echo "     --gateway-id aws-self-hosted-gateway \\"
        echo "     --expiry 2026-12-31T23:59:59Z \\"
        echo "     --query value -o tsv"
        echo ""
        echo "5. Add the gateway token as a GitHub secret:"
        echo "   Secret Name: TF_VAR_apim_gateway_token"
        echo "   Value: <token from step 5>"
        echo ""
        echo "6. Run the AWS deployment workflow"
        echo ""
    fi
else
    # No gh CLI - manual configuration instructions
    echo -e "${YELLOW}GitHub CLI not found. Install it with: brew install gh${NC}"
    echo ""
    echo -e "${BLUE}GitHub Actions Secrets Configuration${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo ""
    echo "Add this secret to your GitHub repository:"
    echo "https://github.com/${GITHUB_REPO}/settings/secrets/actions"
    echo ""
    echo -e "${YELLOW}Repository Secret (click 'New repository secret'):${NC}"
    echo ""
    echo "Secret Name: AWS_ROLE_ARN"
    echo "Value: $ROLE_ARN"
    echo ""
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${BLUE}Next Steps${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo ""
    echo "1. Add the AWS_ROLE_ARN secret to your GitHub repository"
    echo ""
    echo "2. Ensure Azure secrets and variables are configured:"
    echo "   - AZURE_CLIENT_ID"
    echo "   - AZURE_TENANT_ID"
    echo "   - AZURE_SUBSCRIPTION_ID"
    echo "   - APIM_PUBLISHER_NAME (variable)"
    echo "   - APIM_PUBLISHER_EMAIL (variable)"
    echo ""
    echo "3. Run the Azure deployment workflow first to create APIM"
    echo ""
    echo "4. After Azure deployment, generate the APIM gateway token:"
    echo "   az apim gateway token create \\"
    echo "     --resource-group ${PROJECT_NAME}-${ENVIRONMENT}-apim-rg \\"
    echo "     --service-name ${PROJECT_NAME}-${ENVIRONMENT}-apim \\"
    echo "     --gateway-id aws-self-hosted-gateway \\"
    echo "     --expiry 2026-12-31T23:59:59Z \\"
    echo "     --query value -o tsv"
    echo ""
    echo "5. Add the gateway token as a GitHub secret:"
    echo "   Secret Name: TF_VAR_apim_gateway_token"
    echo "   Value: <token from step 5>"
    echo ""
    echo "6. Run the AWS deployment workflow"
    echo ""
fi

echo -e "${GREEN}Done!${NC}"
