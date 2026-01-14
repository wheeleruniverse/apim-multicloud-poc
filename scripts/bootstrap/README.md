# Bootstrap Scripts

This directory contains infrastructure setup scripts that should be run **once** during initial project setup.

## Scripts

### 1. bootstrap-azure.sh
Creates the Azure Storage backend for Terraform state management.

**Usage:**
```bash
./scripts/bootstrap/bootstrap-azure.sh [ENVIRONMENT] [LOCATION]
```

**Example:**
```bash
./scripts/bootstrap/bootstrap-azure.sh dev eastus
```

**What it creates:**
- Resource group: `apim-multicloud-poc-{env}-tfstate-rg`
- Storage account: `steusapimmcpoctfstate`
- Blob container: `tfstate`

**Run this:** Before any Terraform operations.

---

### 2. setup-azure-identity.sh
Creates Azure Managed Identity with Federated Credentials for GitHub Actions OIDC authentication.

**Usage:**
```bash
./scripts/bootstrap/setup-azure-identity.sh [ENVIRONMENT]
```

**Example:**
```bash
./scripts/bootstrap/setup-azure-identity.sh dev
```

**What it creates:**
- Managed Identity: `apim-multicloud-poc-{env}-github-actions`
- Federated credentials for GitHub OIDC (main branch, environment, PRs)
- RBAC role assignments (Contributor, Storage Blob Data Contributor)

**What it configures (if `gh` CLI available):**
- GitHub secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
- GitHub variables: `APIM_PUBLISHER_NAME`, `APIM_PUBLISHER_EMAIL`

**Run this:** After bootstrap-azure.sh, before deploying via GitHub Actions.

---

### 3. setup-aws-identity.sh
Creates AWS IAM OIDC Identity Provider and Role for GitHub Actions authentication.

**Usage:**
```bash
./scripts/bootstrap/setup-aws-identity.sh [ENVIRONMENT] [AWS_REGION]
```

**Example:**
```bash
./scripts/bootstrap/setup-aws-identity.sh dev us-east-1
```

**What it creates:**
- IAM OIDC Identity Provider for GitHub
- IAM Role: `apim-multicloud-poc-{env}-github-actions`
- IAM policies for EKS, VPC, EC2, ECR, and Terraform operations

**What it configures (if `gh` CLI available):**
- GitHub secret: `AWS_ROLE_ARN`

**Run this:** After setup-azure-identity.sh, before deploying AWS resources.

---

## Recommended Setup Order

1. **Bootstrap Azure state backend:**
   ```bash
   ./scripts/bootstrap/bootstrap-azure.sh dev
   ```

2. **Setup Azure OIDC:**
   ```bash
   ./scripts/bootstrap/setup-azure-identity.sh dev
   ```

3. **Setup AWS OIDC:**
   ```bash
   ./scripts/bootstrap/setup-aws-identity.sh dev
   ```

4. **Deploy via GitHub Actions:**
   - Go to: https://github.com/wheeleruniverse/apim-multicloud-poc/actions
   - Run "Terraform - Azure Deployment" workflow

5. **Generate gateway token** (after Azure deployment)

6. **Deploy AWS** via GitHub Actions workflow

---

## Notes

- All scripts are **idempotent** - safe to re-run
- Scripts use `gh` CLI if available to automatically configure GitHub secrets/variables
- If `gh` CLI is not available, scripts display manual instructions
- These scripts are for **initial setup only** - not for ongoing operations
- For operational scripts (testing, monitoring), see `/scripts/tests/` and `/scripts/utilities/`
