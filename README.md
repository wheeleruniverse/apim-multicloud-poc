# Azure APIM Multi-Cloud Proof of Concept

This repository demonstrates Azure API Management (APIM) feasibility in multi-cloud scenarios using the APIM Self-Hosted Gateway deployed to AWS EKS alongside a traditional Azure AKS deployment.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AZURE                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     Azure API Management                             │   │
│  │  ┌─────────────────┐              ┌─────────────────┐               │   │
│  │  │   /azure-api    │              │    /aws-api     │               │   │
│  │  │   (Backend)     │              │   (Backend)     │               │   │
│  │  └────────┬────────┘              └────────┬────────┘               │   │
│  └───────────┼────────────────────────────────┼─────────────────────────┘   │
│              │                                │                             │
│              ▼                                │                             │
│  ┌─────────────────────┐                      │                             │
│  │     Azure AKS       │                      │                             │
│  │  ┌───────────────┐  │                      │                             │
│  │  │  Hello API    │  │                      │                             │
│  │  │ "Hello Azure" │  │                      │                             │
│  │  └───────────────┘  │                      │                             │
│  └─────────────────────┘                      │                             │
└───────────────────────────────────────────────┼─────────────────────────────┘
                                                │
                                                │ (Config Sync)
                                                │
┌───────────────────────────────────────────────┼─────────────────────────────┐
│                              AWS              │                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        AWS EKS Cluster                               │   │
│  │  ┌─────────────────────────┐    ┌─────────────────────────┐         │   │
│  │  │  APIM Self-Hosted GW    │◄───┤     Hello API           │         │   │
│  │  │  (with Config Backup)   │    │   "Hello AWS"           │         │   │
│  │  └─────────────────────────┘    └─────────────────────────┘         │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Features

- **Multi-Cloud API Management**: Single APIM instance managing APIs across Azure and AWS
- **Self-Hosted Gateway**: APIM gateway running in AWS EKS with configuration backup
- **Resilience Testing**: Scripts to simulate Azure outages and verify continued operation
- **Infrastructure as Code**: Complete Terraform configurations for all resources

## Repository Structure

```
.
├── README.md
├── terraform/
│   ├── modules/
│   │   ├── azure-apim/          # Azure API Management module
│   │   ├── azure-aks/           # Azure Kubernetes Service module
│   │   └── aws-eks/             # AWS EKS module with self-hosted gateway
│   └── environments/
│       ├── dev/                 # Development environment
│       └── prod/                # Production environment
├── api/
│   ├── src/                     # Python Flask API source code
│   └── docker/                  # Dockerfile and container configs
├── scripts/
│   ├── tests/                   # Resilience and connectivity tests
│   └── utilities/               # Helper scripts
└── docs/                        # Additional documentation
```

## Prerequisites

- Azure CLI (`az`) authenticated
- AWS CLI (`aws`) configured with appropriate credentials
- Terraform >= 1.5.0
- kubectl
- Docker
- Python 3.9+
- Helm 3.x

## Quick Start

### 1. Clone and Configure

```bash
git clone <repository-url>
cd apim-multicloud-poc

# Copy and edit environment variables
cp terraform/environments/dev/terraform.tfvars.example terraform/environments/dev/terraform.tfvars
```

### 2. Deploy Infrastructure

```bash
cd terraform/environments/dev

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

### 3. Deploy APIs

```bash
# Build and push the API container
cd api
./build-and-push.sh

# Deploy to AKS
kubectl --context aks-apim-poc apply -f k8s/azure/

# Deploy to EKS
kubectl --context eks-apim-poc apply -f k8s/aws/
```

### 4. Run Tests

```bash
# Verify basic connectivity
./scripts/tests/01-verify-connectivity.sh

# Simulate Azure outage
./scripts/tests/02-simulate-azure-outage.sh

# Full resilience test suite
./scripts/tests/03-full-resilience-test.sh
```

## Self-Hosted Gateway Configuration

The self-hosted gateway is configured with **configuration backup enabled**, allowing it to continue operating using the last known configuration when Azure APIM is unreachable.

Key configuration parameters:
- `config.service.syncInterval`: 60 seconds
- `config.service.backupEnabled`: true
- `config.service.backupPath`: /apim/config-backup

## Test Scenarios

| Test | Description | Expected Result |
|------|-------------|-----------------|
| Basic Connectivity | Call both APIs via APIM | Both return "Hello from [Cloud]" |
| Azure Backend Failure | Simulate AKS unavailability | AWS API continues working |
| Azure APIM Outage | Block APIM config sync | Self-hosted GW uses cached config |
| Full Azure Outage | Both APIM and AKS down | AWS API accessible via cached config |
| Recovery | Restore Azure connectivity | Config sync resumes, all APIs work |

## API Endpoints

| Endpoint | Backend | Description |
|----------|---------|-------------|
| `https://<apim-url>/azure-api/hello` | AKS | Returns "Hello from Azure" |
| `https://<apim-url>/aws-api/hello` | EKS via Self-Hosted GW | Returns "Hello from AWS" |
| `https://<shgw-url>/aws-api/hello` | EKS Direct | Direct to self-hosted gateway |

## Blog Post Topics

This POC supports the following blog post themes:

1. **Multi-Cloud API Strategy with Azure APIM**
2. **Achieving API Resilience Across Cloud Providers**
3. **Self-Hosted Gateway: Extending Azure APIM to AWS**
4. **Testing Multi-Cloud Failover Scenarios**

## Cleanup

```bash
cd terraform/environments/dev
terraform destroy
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

MIT License - See LICENSE file for details
