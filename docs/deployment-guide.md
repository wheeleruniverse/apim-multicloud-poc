# Deployment Guide

This guide walks through deploying the APIM Multi-Cloud Proof of Concept from scratch.

## Prerequisites

### Required Tools

```bash
# Verify installations
az --version          # Azure CLI 2.50+
aws --version         # AWS CLI 2.x
terraform --version   # Terraform 1.5+
kubectl version       # kubectl 1.28+
docker --version      # Docker 24+
helm version          # Helm 3.x
```

### Account Setup

1. **Azure Subscription** with permissions to create:
   - Resource Groups
   - API Management instances
   - AKS clusters
   - Container Registries

2. **AWS Account** with permissions to create:
   - VPCs and networking
   - EKS clusters
   - ECR repositories
   - IAM roles

### Authentication

```bash
# Azure login
az login
az account set --subscription "<your-subscription-id>"

# AWS configuration
aws configure
# Or use environment variables:
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-east-1"
```

## Step 1: Clone and Configure

```bash
# Clone the repository
git clone <repository-url>
cd apim-multicloud-poc

# Create your configuration
cp terraform/environments/dev/terraform.tfvars.example \
   terraform/environments/dev/terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
# Required values
apim_publisher_name  = "Your Organization"
apim_publisher_email = "admin@yourorg.com"

# Use a placeholder for now - we'll update this later
apim_gateway_token = "placeholder"
```

## Step 2: Deploy Azure Infrastructure (Phase 1)

We deploy Azure first because we need the APIM gateway token for AWS.

```bash
cd terraform/environments/dev

# Initialize Terraform
terraform init

# Deploy only Azure resources first
terraform apply -target=module.azure_apim -target=module.azure_aks
```

This creates:
- Resource Group
- API Management instance
- AKS cluster
- Container Registry

**Note**: APIM deployment takes 30-45 minutes.

## Step 3: Generate Gateway Token

After APIM is created, generate the self-hosted gateway token:

```bash
# Get the gateway token command from Terraform output
terraform output gateway_token_command

# Run the command (example):
az apim gateway token create \
  --gateway-id aws-self-hosted-gateway \
  --resource-group apim-multicloud-poc-dev-rg \
  --service-name apim-multicloud-poc-dev-apim \
  --expiry "2025-12-31T23:59:59Z"
```

Update `terraform.tfvars` with the generated token:

```hcl
apim_gateway_token = "GatewayKey <token-value>"
```

## Step 4: Deploy AWS Infrastructure (Phase 2)

```bash
# Deploy AWS resources
terraform apply
```

This creates:
- VPC and networking
- EKS cluster
- ECR repository
- Self-hosted gateway deployment
- Kubernetes resources

## Step 5: Configure kubectl Contexts

```bash
# Get AKS credentials
$(terraform output -raw azure_aks_get_credentials)

# Get EKS credentials
$(terraform output -raw aws_eks_update_kubeconfig)

# Verify contexts
kubectl config get-contexts
```

Rename contexts for easier use (optional):

```bash
kubectl config rename-context <aks-context-name> aks-apim-poc
kubectl config rename-context <eks-context-name> eks-apim-poc
```

## Step 6: Build and Deploy API

### Build Container Image

```bash
cd ../../api

# Get registry URLs from Terraform
ACR_NAME=$(cd ../terraform/environments/dev && terraform output -raw azure_acr_login_server | cut -d. -f1)
ECR_REPO=$(cd ../terraform/environments/dev && terraform output -raw aws_ecr_repository_url)

# Build and push to both registries
./build-and-push.sh \
  --acr-name $ACR_NAME \
  --ecr-repo $ECR_REPO \
  --tag latest
```

### Deploy to AKS

```bash
# Update the image reference in the manifest
sed -i "s/\${ACR_NAME}/$ACR_NAME/g" k8s/azure/deployment.yaml

# Deploy to AKS
kubectl --context aks-apim-poc apply -f k8s/azure/deployment.yaml

# Verify deployment
kubectl --context aks-apim-poc get pods -n hello-api
```

### Deploy to EKS

```bash
# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="us-east-1"

# Update the image reference
sed -i "s/\${AWS_ACCOUNT_ID}/$AWS_ACCOUNT_ID/g" k8s/aws/deployment.yaml
sed -i "s/\${AWS_REGION}/$AWS_REGION/g" k8s/aws/deployment.yaml

# Deploy to EKS
kubectl --context eks-apim-poc apply -f k8s/aws/deployment.yaml

# Verify deployment
kubectl --context eks-apim-poc get pods -n hello-api
```

## Step 7: Verify Deployment

### Get Endpoint URLs

```bash
# APIM Gateway URL
cd ../terraform/environments/dev
APIM_URL=$(terraform output -raw azure_apim_gateway_url)

# Self-Hosted Gateway URL
SHGW_URL=$(kubectl --context eks-apim-poc get svc apim-gateway -n apim-gateway \
  -o jsonpath='http://{.status.loadBalancer.ingress[0].hostname}')

echo "APIM Gateway: $APIM_URL"
echo "Self-Hosted Gateway: $SHGW_URL"
```

### Test Connectivity

```bash
# Test Azure API through APIM
curl "$APIM_URL/azure-api/hello"

# Test AWS API through APIM
curl "$APIM_URL/aws-api/hello"

# Test AWS API directly through Self-Hosted Gateway
curl "$SHGW_URL/aws-api/hello"
```

Expected responses:

```json
// Azure API
{
  "message": "Hello from Azure!",
  "source": "Azure",
  "timestamp": "2024-01-15T10:30:00Z",
  ...
}

// AWS API
{
  "message": "Hello from AWS!",
  "source": "AWS",
  "timestamp": "2024-01-15T10:30:00Z",
  ...
}
```

## Step 8: Run Verification Tests

```bash
cd ../../scripts/tests

# Basic connectivity test
./01-verify-connectivity.sh \
  --apim-url "$APIM_URL" \
  --shgw-url "$SHGW_URL"
```

## Troubleshooting

### APIM Deployment Fails

```bash
# Check APIM deployment status
az apim show -n apim-multicloud-poc-dev-apim -g apim-multicloud-poc-dev-rg

# View detailed errors
az monitor activity-log list \
  --resource-group apim-multicloud-poc-dev-rg \
  --offset 1h
```

### Self-Hosted Gateway Not Connecting

```bash
# Check gateway pod logs
kubectl --context eks-apim-poc logs -l app=apim-gateway -n apim-gateway

# Verify gateway token is correct
kubectl --context eks-apim-poc get secret apim-gateway-token -n apim-gateway -o yaml

# Check gateway deployment status
kubectl --context eks-apim-poc describe deployment apim-self-hosted-gateway -n apim-gateway
```

### API Pods Not Starting

```bash
# Check pod status and events
kubectl --context eks-apim-poc describe pods -n hello-api

# Check image pull status
kubectl --context eks-apim-poc get events -n hello-api --sort-by=.lastTimestamp
```

### Network Connectivity Issues

```bash
# Test DNS resolution from gateway pod
kubectl --context eks-apim-poc exec -it \
  $(kubectl --context eks-apim-poc get pod -l app=apim-gateway -n apim-gateway -o name | head -1) \
  -n apim-gateway -- nslookup hello-api.hello-api.svc.cluster.local

# Test service connectivity
kubectl --context eks-apim-poc exec -it \
  $(kubectl --context eks-apim-poc get pod -l app=apim-gateway -n apim-gateway -o name | head -1) \
  -n apim-gateway -- curl http://hello-api.hello-api.svc.cluster.local/health
```

## Clean Up

To destroy all resources:

```bash
cd terraform/environments/dev

# Destroy all resources
terraform destroy

# Remove kubectl contexts (optional)
kubectl config delete-context aks-apim-poc
kubectl config delete-context eks-apim-poc
```

## Next Steps

After successful deployment:

1. Run the full resilience test suite: `./scripts/tests/03-full-resilience-test.sh`
2. Simulate Azure outage: `./scripts/tests/02-simulate-azure-outage.sh`
3. Review the architecture documentation: `docs/architecture.md`
4. Set up monitoring and alerting
