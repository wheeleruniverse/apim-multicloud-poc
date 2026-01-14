# GitHub Actions Setup Guide

This guide walks you through setting up GitHub Actions workflows for deploying your APIM multi-cloud infrastructure using OIDC authentication.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
  - [Step 1: Azure OIDC Setup](#step-1-azure-oidc-setup)
  - [Step 2: AWS OIDC Setup](#step-2-aws-oidc-setup)
  - [Verify Configuration](#verify-configuration-optional)
- [Deployment Process](#deployment-process)
  - [Phase 1: Azure Deployment](#phase-1-azure-deployment)
  - [Phase 2: Gateway Token Generation](#phase-2-gateway-token-generation)
  - [Phase 3: AWS Deployment](#phase-3-aws-deployment)
- [Workflow Usage](#workflow-usage)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Token Rotation](#token-rotation)
- [Destroying Infrastructure](#destroying-infrastructure)

---

## Overview

This setup uses **OIDC (OpenID Connect)** for authentication, which means:
- ✅ No long-lived credentials stored anywhere
- ✅ Automatic token rotation
- ✅ Scoped access to your repository
- ✅ Full audit trail via GitHub Actions logs
- ✅ Follows cloud security best practices

**Architecture:**
- **Azure**: Managed Identity with Federated Credentials
- **AWS**: IAM OIDC Identity Provider with IAM Role
- **Terraform State**: Azure Blob Storage (already configured)
- **Workflows**: Separate workflows for Azure and AWS deployments

---

## Prerequisites

Before starting, ensure you have:

- [x] Azure subscription with Pay-as-You-Go billing
- [x] AWS account with administrative access
- [x] GitHub repository: `wheeleruniverse/apim-multicloud-poc`
- [x] Azure CLI installed locally (`az --version`)
- [x] AWS CLI installed locally (`aws --version`)
- [x] **GitHub CLI installed** (`gh --version`) - **Recommended** for automatic setup
- [x] Authenticated to Azure (`az login`)
- [x] Authenticated to AWS (`aws configure` or `AWS_PROFILE` set)
- [x] **Authenticated to GitHub** (`gh auth login`) - **Recommended**
- [x] Terraform state backend created (run `./scripts/bootstrap/bootstrap-azure.sh` if not done)

**Note:** GitHub CLI (`gh`) is highly recommended as it automates secret and variable configuration. Without it, you'll need to manually add secrets via the GitHub web UI.

---

## Initial Setup

### Step 1: Azure OIDC Setup

This step creates an Azure Managed Identity with Federated Credentials for GitHub Actions, and optionally configures all GitHub secrets and variables automatically.

**Run the setup script:**

```bash
cd /path/to/apim-multicloud-poc
chmod +x scripts/setup-azure-identity.sh
./scripts/bootstrap/setup-azure-identity.sh dev
```

**What this script does:**
1. Creates an Azure Managed Identity: `apim-multicloud-poc-dev-github-actions`
2. Configures Federated Credentials for:
   - Main branch deployments
   - Environment-specific deployments
   - Pull request plans
3. Assigns RBAC roles:
   - `Contributor` on subscription (to create resources)
   - `Storage Blob Data Contributor` on tfstate storage account (for backend access)
4. **If `gh` CLI is installed:** Automatically configures GitHub secrets and variables
5. **If `gh` CLI not installed:** Displays manual configuration instructions

**Interactive prompts (with gh CLI):**

```
GitHub CLI detected! Would you like to automatically configure secrets and variables? (y/n)
y

Configuring GitHub secrets...
✓ Set AZURE_CLIENT_ID
✓ Set AZURE_TENANT_ID
✓ Set AZURE_SUBSCRIPTION_ID

Configuring GitHub variables...

Enter APIM Publisher Name (e.g., wheeleruniverse):
wheeleruniverse

Enter APIM Publisher Email (e.g., justin.wheeler@wheeleruniverse.com):
justin.wheeler@wheeleruniverse.com

✓ Set APIM_PUBLISHER_NAME
✓ Set APIM_PUBLISHER_EMAIL

✓ All GitHub secrets and variables configured!
```

**That's it!** If you used `gh` CLI, all Azure secrets and variables are now configured in GitHub. Skip to Step 2.

**Manual configuration (without gh CLI):**

If you don't have `gh` CLI installed, the script will display the values you need to add manually:

```
============================================================
Azure Managed Identity Setup Complete!
============================================================

Add these secrets to your GitHub repository:
https://github.com/wheeleruniverse/apim-multicloud-poc/settings/secrets/actions

Secret Name: AZURE_CLIENT_ID
Value: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

Secret Name: AZURE_TENANT_ID
Value: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

Secret Name: AZURE_SUBSCRIPTION_ID
Value: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

Add these variables:
https://github.com/wheeleruniverse/apim-multicloud-poc/settings/variables/actions

Variable Name: APIM_PUBLISHER_NAME
Variable Name: APIM_PUBLISHER_EMAIL
```

---

### Step 2: AWS OIDC Setup

This step creates an AWS IAM OIDC Identity Provider and IAM Role for GitHub Actions, and optionally configures the GitHub secret automatically.

**Run the setup script:**

```bash
chmod +x scripts/setup-aws-identity.sh
./scripts/bootstrap/setup-aws-identity.sh dev
# Or with custom region:
./scripts/bootstrap/setup-aws-identity.sh dev us-west-2
```

**What this script does:**
1. Creates an IAM OIDC Identity Provider for GitHub
2. Creates an IAM Role: `apim-multicloud-poc-dev-github-actions`
3. Configures trust policy for your GitHub repository
4. Attaches AWS managed policies:
   - `AmazonEKSClusterPolicy`
   - `AmazonEKSWorkerNodePolicy`
   - `AmazonEC2ContainerRegistryFullAccess`
   - `AmazonVPCFullAccess`
5. Creates inline policy for additional Terraform operations (IAM, KMS, Logs, etc.)
6. **If `gh` CLI is installed:** Automatically configures AWS_ROLE_ARN secret
7. **If `gh` CLI not installed:** Displays manual configuration instructions

**Interactive prompt (with gh CLI):**

```
GitHub CLI detected! Would you like to automatically configure the AWS secret? (y/n)
y

Configuring GitHub secret...
✓ Set AWS_ROLE_ARN

✓ GitHub secret configured!
```

**That's it!** If you used `gh` CLI, the AWS secret is now configured. You're ready to deploy!

**Manual configuration (without gh CLI):**

If you don't have `gh` CLI installed, the script will display:

```
============================================================
AWS IAM OIDC Setup Complete!
============================================================

Add this secret to your GitHub repository:
https://github.com/wheeleruniverse/apim-multicloud-poc/settings/secrets/actions

Secret Name: AWS_ROLE_ARN
Value: arn:aws:iam::123456789012:role/apim-multicloud-poc-dev-github-actions
```

---

### Verify Configuration (Optional)

If you used `gh` CLI, you can verify all secrets and variables were configured:

```bash
# List secrets (values are hidden)
gh secret list --repo wheeleruniverse/apim-multicloud-poc

# List variables
gh variable list --repo wheeleruniverse/apim-multicloud-poc
```

**Expected secrets:**
- AZURE_CLIENT_ID
- AZURE_TENANT_ID
- AZURE_SUBSCRIPTION_ID
- AWS_ROLE_ARN

**Expected variables:**
- APIM_PUBLISHER_NAME
- APIM_PUBLISHER_EMAIL

**Note:** You'll add `TF_VAR_apim_gateway_token` secret later, after Azure deployment completes.

---

## Deployment Process

### Phase 1: Azure Deployment

Deploy Azure API Management and Azure Kubernetes Service.

**Steps:**

1. Navigate to GitHub Actions:
   ```
   https://github.com/wheeleruniverse/apim-multicloud-poc/actions
   ```

2. Select workflow: **"Terraform - Azure Deployment"**

3. Click **"Run workflow"** button (top right)

4. Configure workflow inputs:
   - **Operation**: `apply`
   - **Environment**: `dev`

5. Click **"Run workflow"**

6. Monitor the workflow execution
   - Expected duration: **30-60 minutes** (APIM creation is slow)
   - Watch for any errors in the logs

7. Wait for completion
   - Status will show ✅ green checkmark when done
   - Review the "Display Next Steps" output

**What gets deployed:**
- Azure Resource Groups
- Azure API Management (Developer SKU)
- Azure Kubernetes Service (AKS)
- Virtual Networks and Subnets
- Log Analytics Workspace
- Container Registry (ACR)

**After successful deployment**, you'll see output like:

```
============================================================
Azure Deployment Complete!
============================================================

APIM Gateway URL: https://apim-multicloud-poc-dev-apim.azure-api.net

============================================================
NEXT STEP: Generate APIM Gateway Token
============================================================

Run this command to generate the gateway token:

az apim gateway token create \
  --resource-group apim-multicloud-poc-dev-apim-rg \
  --service-name apim-multicloud-poc-dev-apim \
  --gateway-id aws-self-hosted-gateway \
  --expiry 2026-12-31T23:59:59Z \
  --query value -o tsv
```

**Copy this command** - you'll need it in Phase 2.

---

### Phase 2: Gateway Token Generation

After Azure deployment completes, generate the APIM gateway token for AWS deployment.

**Steps:**

1. **Copy the command from the Azure workflow output** (from Phase 1, step 7)

2. **Run the command locally** or in Azure Cloud Shell:

   ```bash
   az apim gateway token create \
     --resource-group apim-multicloud-poc-dev-apim-rg \
     --service-name apim-multicloud-poc-dev-apim \
     --gateway-id aws-self-hosted-gateway \
     --expiry 2026-12-31T23:59:59Z \
     --query value -o tsv
   ```

3. **Add the token to GitHub**

   **Option A: Using gh CLI (Recommended)**

   Pipe the token directly to `gh`:

   ```bash
   # Generate and add in one command
   az apim gateway token create \
     --resource-group apim-multicloud-poc-dev-apim-rg \
     --service-name apim-multicloud-poc-dev-apim \
     --gateway-id aws-self-hosted-gateway \
     --expiry 2026-12-31T23:59:59Z \
     --query value -o tsv | gh secret set TF_VAR_apim_gateway_token --repo wheeleruniverse/apim-multicloud-poc

   # You'll see:
   # ✓ Set Actions secret TF_VAR_apim_gateway_token for wheeleruniverse/apim-multicloud-poc
   ```

   **Option B: Manual via GitHub UI**

   - Copy the token output from step 2
   - Go to: `https://github.com/wheeleruniverse/apim-multicloud-poc/settings/secrets/actions`
   - Click "New repository secret"
   - **Name**: `TF_VAR_apim_gateway_token`
   - **Value**: Paste the token
   - Click "Add secret"

**Important:** The token is sensitive - treat it like a password. It allows the AWS self-hosted gateway to authenticate to Azure APIM.

---

### Phase 3: AWS Deployment

Deploy AWS EKS cluster with APIM self-hosted gateway.

**Steps:**

1. **Ensure gateway token is added** (from Phase 2)

2. Navigate to GitHub Actions:
   ```
   https://github.com/wheeleruniverse/apim-multicloud-poc/actions
   ```

3. Select workflow: **"Terraform - AWS Deployment"**

4. Click **"Run workflow"** button

5. Configure workflow inputs:
   - **Operation**: `apply`
   - **Environment**: `dev`

6. Click **"Run workflow"**

7. Monitor the workflow execution
   - Expected duration: **15-25 minutes**
   - The workflow will fail fast if gateway token is missing

8. Wait for completion

**What gets deployed:**
- AWS VPC with public/private subnets
- AWS EKS cluster
- EKS node groups
- APIM Self-Hosted Gateway (deployed to EKS)
- Network Load Balancer for gateway
- ECR repository
- Security groups and IAM roles

**After successful deployment**, you'll see:

```
============================================================
AWS Deployment Complete!
============================================================

ECR Repository: 123456789012.dkr.ecr.us-east-1.amazonaws.com/apim-multicloud-poc-dev

============================================================
Next Steps
============================================================

1. Get EKS cluster credentials:

aws eks update-kubeconfig --name apim-multicloud-poc-dev-eks --region us-east-1 --alias apim-poc-dev-eks

2. Verify self-hosted gateway is running:

   kubectl get pods -n apim-gateway
   kubectl logs -n apim-gateway deployment/apim-self-hosted-gateway

3. Build and deploy your API containers:

   cd api
   ./build-and-push.sh --all
```

---

## Workflow Usage

### Running a Plan (Dry Run)

To see what changes Terraform will make without actually applying them:

**Azure Plan:**
1. Go to Actions → "Terraform - Azure Deployment"
2. Run workflow with:
   - Operation: `plan`
   - Environment: `dev`
3. Review the plan output in the logs

**AWS Plan:**
1. Go to Actions → "Terraform - AWS Deployment"
2. Run workflow with:
   - Operation: `plan`
   - Environment: `dev`
3. Review the plan output in the logs

### Re-deploying (Updating Infrastructure)

If you make changes to your Terraform configuration and want to apply them:

1. Commit and push your changes to the repository
2. Run the appropriate workflow (Azure or AWS) with `operation: apply`
3. Terraform will show what changes will be made and apply them

### Workflow Artifacts

Both workflows upload the plan output as artifacts:
- Retention: 30 days
- Download from: Actions → Workflow Run → Artifacts section

---

## Verification

### After Azure Deployment

**Verify in Azure Portal:**

1. **Resource Groups:**
   - `apim-multicloud-poc-dev-apim-rg` - Contains APIM instance
   - `apim-multicloud-poc-dev-aks-rg` - Contains AKS cluster

2. **API Management:**
   - Navigate to APIM instance
   - Check "APIs" section - should see `azure-hello-api` and `aws-hello-api`
   - Check "Gateways" section - should see `aws-self-hosted-gateway`

3. **AKS Cluster:**
   - Navigate to AKS cluster
   - Should show "Running" status

**Verify with Azure CLI:**

```bash
# Get AKS credentials
az aks get-credentials --resource-group apim-multicloud-poc-dev-aks-rg --name apim-multicloud-poc-dev-aks

# Check cluster nodes
kubectl get nodes

# Expected output: 1-2 nodes in Ready state
```

### After AWS Deployment

**Verify in AWS Console:**

1. **EKS Cluster:**
   - Navigate to EKS service
   - Should see cluster: `apim-multicloud-poc-dev-eks`
   - Status: Active

2. **VPC:**
   - Navigate to VPC service
   - Should see new VPC with public/private subnets

3. **Load Balancers:**
   - Navigate to EC2 → Load Balancers
   - Should see NLB for self-hosted gateway

**Verify with AWS CLI:**

```bash
# Get EKS credentials
aws eks update-kubeconfig --name apim-multicloud-poc-dev-eks --region us-east-1

# Check self-hosted gateway pods
kubectl get pods -n apim-gateway

# Expected output: 1-2 gateway pods in Running state

# Check gateway logs
kubectl logs -n apim-gateway deployment/apim-self-hosted-gateway | tail -50

# Look for: "Configuration synced successfully" or similar messages
```

### End-to-End Testing

Run the provided test scripts:

```bash
cd scripts/tests

# Test basic connectivity
./01-verify-connectivity.sh

# Test resilience (optional - simulates Azure outage)
./02-simulate-azure-outage.sh

# Full test suite
./03-full-resilience-test.sh
```

**Expected results:**
- Azure API endpoint responds: `https://<apim-gateway-url>/azure-api/hello`
- AWS API endpoint responds: `https://<apim-gateway-url>/aws-api/hello`
- Both return `{"message": "Hello from Azure/AWS!"}`

---

## Troubleshooting

### Issue: "Storage account not found" during Terraform Init

**Cause:** Terraform backend storage account doesn't exist.

**Solution:**
```bash
cd scripts
./bootstrap-azure.sh
```

This creates the storage account for Terraform state.

---

### Issue: "Azure authentication failed" in workflow

**Symptoms:**
- Error: `AADSTS70021: No matching federated identity record found`
- Error: `Failed to get Azure credentials`

**Possible causes:**
1. GitHub secrets are incorrect
2. Managed identity doesn't exist
3. Federated credentials not configured correctly

**Solution:**

1. Verify secrets in GitHub match the output from `setup-azure-identity.sh`
2. Re-run the Azure setup script:
   ```bash
   ./scripts/bootstrap/setup-azure-identity.sh dev
   ```
3. Check the managed identity exists:
   ```bash
   az identity show --name apim-multicloud-poc-dev-github-actions --resource-group apim-multicloud-poc-dev-identity-rg
   ```

---

### Issue: "AWS authentication failed" in workflow

**Symptoms:**
- Error: `Unable to assume role`
- Error: `AccessDenied`

**Possible causes:**
1. AWS_ROLE_ARN secret is incorrect
2. OIDC provider doesn't exist
3. IAM role trust policy is misconfigured

**Solution:**

1. Verify AWS_ROLE_ARN secret matches the role ARN from setup script
2. Re-run the AWS setup script:
   ```bash
   ./scripts/bootstrap/setup-aws-identity.sh dev
   ```
3. Check the OIDC provider exists:
   ```bash
   aws iam list-open-id-connect-providers
   ```
4. Check the role exists:
   ```bash
   aws iam get-role --role-name apim-multicloud-poc-dev-github-actions
   ```

---

### Issue: "Gateway token not found" in AWS workflow

**Symptoms:**
- AWS workflow fails with: `ERROR: Gateway token not found!`

**Cause:** The `TF_VAR_apim_gateway_token` secret hasn't been added to GitHub.

**Solution:**

1. Ensure Azure deployment completed successfully
2. Generate the gateway token:
   ```bash
   az apim gateway token create \
     --resource-group apim-multicloud-poc-dev-apim-rg \
     --service-name apim-multicloud-poc-dev-apim \
     --gateway-id aws-self-hosted-gateway \
     --expiry 2026-12-31T23:59:59Z \
     --query value -o tsv
   ```
3. Add it to GitHub Secrets as `TF_VAR_apim_gateway_token`

---

### Issue: "APIM creation timeout" or "deployment taking hours"

**Symptoms:**
- Azure workflow runs for 60+ minutes
- APIM creation seems stuck

**Cause:** APIM creation is genuinely slow (30-90 minutes is normal for Developer SKU).

**Solution:**

1. **Check Azure Portal** to see actual APIM status:
   - Navigate to resource group: `apim-multicloud-poc-dev-apim-rg`
   - Check APIM instance status
   - If status is "Activating" or "Updating", it's still in progress

2. **If stuck in "Failed" state:**
   - Run destroy workflow: `operation: destroy`
   - Wait for destroy to complete
   - Re-run apply workflow

3. **If workflow times out but APIM is still creating:**
   - The workflow may timeout after 60 minutes
   - APIM will continue creating in Azure
   - Once APIM shows "Online" status in portal, you can proceed to gateway token generation
   - You may need to manually run `terraform apply` locally or re-run the workflow

---

### Issue: "Self-hosted gateway not connecting to APIM"

**Symptoms:**
- Gateway pods running but logs show connection errors
- Gateway can't sync configuration from Azure

**Cause:** Gateway token is invalid, expired, or incorrectly configured.

**Solution:**

1. Check gateway logs:
   ```bash
   kubectl logs -n apim-gateway deployment/apim-self-hosted-gateway
   ```

2. Look for authentication errors

3. Regenerate gateway token:
   ```bash
   az apim gateway token create \
     --resource-group apim-multicloud-poc-dev-apim-rg \
     --service-name apim-multicloud-poc-dev-apim \
     --gateway-id aws-self-hosted-gateway \
     --expiry 2026-12-31T23:59:59Z \
     --query value -o tsv
   ```

4. Update GitHub Secret: `TF_VAR_apim_gateway_token`

5. Re-run AWS workflow with `operation: apply`

---

### Issue: "Insufficient permissions" errors

**Symptoms:**
- Terraform errors about lacking permissions
- Error creating resources

**Azure permissions issue:**

**Solution:**
```bash
# Check role assignments
az role assignment list --assignee <client-id-from-setup>

# If missing, re-run setup script
./scripts/bootstrap/setup-azure-identity.sh dev
```

**AWS permissions issue:**

**Solution:**
```bash
# Check role policies
aws iam list-attached-role-policies --role-name apim-multicloud-poc-dev-github-actions
aws iam list-role-policies --role-name apim-multicloud-poc-dev-github-actions

# If missing, re-run setup script
./scripts/bootstrap/setup-aws-identity.sh dev
```

---

## Token Rotation

The APIM gateway token should be rotated periodically for security.

**When to rotate:**
- Before token expiration (check expiry date when you generated it)
- After a security incident
- Every 6-12 months as best practice

**How to rotate:**

**Option A: Using gh CLI (One Command)**

```bash
# Generate new token and update GitHub secret in one command
az apim gateway token create \
  --resource-group apim-multicloud-poc-dev-apim-rg \
  --service-name apim-multicloud-poc-dev-apim \
  --gateway-id aws-self-hosted-gateway \
  --expiry 2026-12-31T23:59:59Z \
  --query value -o tsv | gh secret set TF_VAR_apim_gateway_token --repo wheeleruniverse/apim-multicloud-poc

# You'll see: ✓ Set Actions secret TF_VAR_apim_gateway_token for wheeleruniverse/apim-multicloud-poc
```

**Option B: Manual via GitHub UI**

1. Generate a new token:
   ```bash
   az apim gateway token create \
     --resource-group apim-multicloud-poc-dev-apim-rg \
     --service-name apim-multicloud-poc-dev-apim \
     --gateway-id aws-self-hosted-gateway \
     --expiry 2026-12-31T23:59:59Z \
     --query value -o tsv
   ```

2. Update the GitHub Secret:
   - Go to: `https://github.com/wheeleruniverse/apim-multicloud-poc/settings/secrets/actions`
   - Click on `TF_VAR_apim_gateway_token`
   - Click "Update secret"
   - Paste the new token
   - Click "Update secret"

3. Re-deploy AWS infrastructure to update the gateway:
   - Run "Terraform - AWS Deployment" workflow
   - Operation: `apply`
   - Environment: `dev`

4. Verify gateway reconnects:
   ```bash
   kubectl logs -n apim-gateway deployment/apim-self-hosted-gateway | tail -50
   ```
   Look for successful configuration sync messages.

---

## Destroying Infrastructure

### Important Notes

- **Destroy AWS first, then Azure** (reverse order of deployment)
- Destroy operations require **manual approval** (GitHub Environment protection)
- All data will be lost (ensure you have backups if needed)

### Destroy AWS Resources

1. Go to Actions → "Terraform - AWS Deployment"
2. Run workflow with:
   - Operation: `destroy`
   - Environment: `dev`
3. **Wait for approval prompt** (if environment protection is configured)
4. Review what will be destroyed
5. Click "Approve and deploy" to proceed
6. Wait for destruction to complete (10-15 minutes)

**Resources destroyed:**
- EKS cluster
- EKS node groups
- Self-hosted gateway
- VPC and subnets
- Load balancers
- Security groups
- ECR repository

### Destroy Azure Resources

1. Go to Actions → "Terraform - Azure Deployment"
2. Run workflow with:
   - Operation: `destroy`
   - Environment: `dev`
3. **Wait for approval prompt** (if environment protection is configured)
4. Review what will be destroyed
5. Click "Approve and deploy" to proceed
6. Wait for destruction to complete (20-30 minutes)

**Resources destroyed:**
- APIM instance
- AKS cluster
- Container Registry (ACR)
- Virtual networks
- Log Analytics workspace

**Note:** The following are NOT destroyed and must be manually deleted if desired:
- Terraform state storage account (by design - contains state history)
- Managed identity for GitHub Actions (reusable for next deployment)
- IAM role in AWS (reusable for next deployment)

---

## Environment Protection Setup (Optional)

To require manual approval before destroy operations:

1. Go to: `https://github.com/wheeleruniverse/apim-multicloud-poc/settings/environments`

2. Create environment: `dev-azure-destroy-approval`
   - Click "New environment"
   - Name: `dev-azure-destroy-approval`
   - Add "Required reviewers": Select yourself or team members
   - Save

3. Create environment: `dev-aws-destroy-approval`
   - Same process as above
   - Name: `dev-aws-destroy-approval`

**Result:** When running destroy operations, GitHub Actions will pause and wait for manual approval before proceeding.

---

## Additional Resources

- [Azure Managed Identity Documentation](https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/)
- [GitHub Actions OIDC Documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [AWS IAM OIDC Identity Providers](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [Terraform Azure Backend](https://www.terraform.io/docs/language/settings/backends/azurerm.html)

---

## Summary Checklist

**Initial Setup (with gh CLI - Recommended):**
- [ ] Install and authenticate: `gh auth login`
- [ ] Run `./scripts/bootstrap/setup-azure-identity.sh dev` and answer 'y' to prompts
- [ ] Enter APIM publisher name and email when prompted
- [ ] Run `./scripts/bootstrap/setup-aws-identity.sh dev` and answer 'y' to prompt
- [ ] Done! All secrets and variables configured automatically

**Initial Setup (without gh CLI - Manual):**
- [ ] Run `./scripts/bootstrap/setup-azure-identity.sh dev`
- [ ] Manually add 3 Azure secrets to GitHub
- [ ] Manually add 2 variables to GitHub (APIM_PUBLISHER_NAME, APIM_PUBLISHER_EMAIL)
- [ ] Run `./scripts/bootstrap/setup-aws-identity.sh dev`
- [ ] Manually add AWS_ROLE_ARN secret to GitHub

**Deployment:**
- [ ] Run Azure workflow (operation: apply, environment: dev)
- [ ] Wait 30-60 minutes for APIM creation
- [ ] Generate gateway token with `az apim gateway token create` command
- [ ] Add token: `echo '<token>' | gh secret set TF_VAR_apim_gateway_token --repo wheeleruniverse/apim-multicloud-poc`
- [ ] Run AWS workflow (operation: apply, environment: dev)
- [ ] Wait 15-25 minutes for EKS creation

**Verification:**
- [ ] Check Azure Portal for APIM and AKS resources
- [ ] Check AWS Console for EKS cluster
- [ ] Run `./scripts/tests/01-verify-connectivity.sh`
- [ ] Verify both `/azure-api/hello` and `/aws-api/hello` endpoints respond

---

**Questions or Issues?**

If you encounter problems not covered in this guide:
1. Check the workflow logs in GitHub Actions
2. Review the Troubleshooting section above
3. Check Azure/AWS console for resource status
4. Verify all secrets and variables are correctly configured

Happy deploying! 🚀
