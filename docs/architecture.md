# Architecture Guide

## Overview

This document describes the architecture of the APIM Multi-Cloud Proof of Concept, demonstrating Azure API Management's capability to manage APIs across both Azure and AWS cloud providers.

## High-Level Architecture

```
                                    ┌─────────────────────────────────────┐
                                    │            End Users                │
                                    └─────────────────┬───────────────────┘
                                                      │
                                                      │ HTTPS
                                                      ▼
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│                                        AZURE                                             │
│                                                                                          │
│    ┌───────────────────────────────────────────────────────────────────────────────┐     │
│    │                        Azure API Management (APIM)                            │     │
│    │                                                                               │     │
│    │    ┌─────────────────┐                    ┌─────────────────┐                 │     │
│    │    │   Managed       │                    │   Self-Hosted   │                 │     │
│    │    │   Gateway       │                    │   Gateway       │                 │     │
│    │    │                 │                    │   Config Sync   │                 │     │
│    │    └────────┬────────┘                    └────────┬────────┘                 │     │
│    │             │                                      │                          │     │
│    │    ┌────────┴────────┐                    ┌────────┴────────┐                 │     │
│    │    │  /azure-api/*   │                    │   /aws-api/*    │                 │     │
│    │    │  Azure Backend  │                    │   AWS Backend   │                 │     │
│    │    └────────┬────────┘                    └────────┬────────┘                 │     │
│    └─────────────┼──────────────────────────────────────┼──────────────────────────┘     │
│                  │                                      │                                │
│                  ▼                                      │ Configuration                  │
│    ┌─────────────────────────┐                          │ & Policy Sync                  │
│    │      Azure AKS          │                          │                                │
│    │                         │                          │                                │
│    │  ┌───────────────────┐  │                          │                                │
│    │  │    Hello API      │  │                          │                                │
│    │  │ "Hello from Azure"│  │                          │                                │
│    │  └───────────────────┘  │                          │                                │
│    │                         │                          │                                │
│    └─────────────────────────┘                          │                                │
│                                                         │                                │
└─────────────────────────────────────────────────────────┼────────────────────────────────┘
                                                          │
                                                          │ HTTPS (Outbound from AWS)
                                                          │
┌─────────────────────────────────────────────────────────┼────────────────────────────────┐
│                                       AWS               │                                │
│                                                         │                                │
│    ┌──────────────────────────────────────────────────────────────────────────────┐      │
│    │                           AWS EKS Cluster                                    │      │
│    │                                                                              │      │
│    │    ┌─────────────────────────────────┐    ┌──────────────────────────────┐   │      │
│    │    │   APIM Self-Hosted Gateway      │    │        Hello API             │   │      │
│    │    │                                 │    │                              │   │      │
│    │    │  • Config Backup Enabled        │◄───┤    "Hello from AWS"          │   │      │
│    │    │  • 60s Sync Interval            │    │                              │   │      │
│    │    │  • Persistent Volume for Cache  │    │    Pods: 2 replicas          │   │      │
│    │    │                                 │    │                              │   │      │
│    │    │  Pods: 2 replicas               │    └──────────────────────────────┘   │      │
│    │    └─────────────────────────────────┘                                       │      │
│    │                                                                              │      │
│    └──────────────────────────────────────────────────────────────────────────────┘      │
│                                                                                          │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

## Components

### Azure Components

#### Azure API Management (APIM)

- **SKU**: Developer (for POC) / Premium (for production)
- **Location**: East US
- **Features Used**:
  - API definitions and policies
  - Self-hosted gateway management
  - Configuration synchronization

#### Azure AKS Cluster

- **Purpose**: Hosts the "Azure" instance of the Hello API
- **Node Pool**: 2 nodes, Standard_DS2_v2
- **Networking**: Azure CNI with Network Policy

#### Azure Container Registry (ACR)

- **Purpose**: Stores container images for AKS deployment
- **Integration**: AKS has pull access via managed identity

### AWS Components

#### AWS EKS Cluster

- **Purpose**: Hosts the Self-Hosted Gateway and "AWS" instance of Hello API
- **Node Group**: 2 nodes, t3.medium
- **Networking**: VPC with public/private subnets

#### APIM Self-Hosted Gateway

The self-hosted gateway is the critical component enabling multi-cloud API management:

```yaml
Key Configuration:
  - Image: mcr.microsoft.com/azure-api-management/gateway:v2
  - Replicas: 2 (for high availability)
  - Config Sync Interval: 60 seconds
  - Config Backup: Enabled (persistent volume)
  - Retry Settings: 10 retries, 30s interval
```

##### Configuration Backup

The self-hosted gateway stores configuration locally, enabling continued operation during Azure outages:

```
/apim/config-backup/
├── apis/
├── products/
├── policies/
└── gateway-config.json
```

#### AWS ECR Repository

- **Purpose**: Stores container images for EKS deployment
- **Lifecycle Policy**: Keeps last 10 images

## Data Flow

### Normal Operation

1. Client sends request to APIM Gateway URL
2. APIM routes based on API path:
   - `/azure-api/*` → Direct to AKS backend
   - `/aws-api/*` → Through Self-Hosted Gateway → EKS backend
3. Response returns through the same path

### During Azure Outage

1. Self-hosted gateway loses connection to APIM
2. Gateway uses locally cached configuration
3. AWS API requests continue to work
4. Azure API requests fail (expected)
5. When connectivity restores, gateway re-syncs configuration

## Network Architecture

### Azure Network

```
Virtual Network: 10.1.0.0/16
├── AKS Subnet: 10.1.0.0/22
├── APIM Subnet: 10.1.4.0/24
└── Management Subnet: 10.1.5.0/24
```

### AWS Network

```
VPC: 10.0.0.0/16
├── Private Subnets (EKS Nodes):
│   ├── 10.0.1.0/24 (AZ-a)
│   ├── 10.0.2.0/24 (AZ-b)
│   └── 10.0.3.0/24 (AZ-c)
└── Public Subnets (Load Balancers):
    ├── 10.0.101.0/24 (AZ-a)
    ├── 10.0.102.0/24 (AZ-b)
    └── 10.0.103.0/24 (AZ-c)
```

## Security Considerations

### Authentication

1. **APIM Gateway Token**: Self-hosted gateway authenticates to APIM using a gateway token
2. **Service-to-Service**: APIs are accessed without subscription keys (for POC simplicity)

### Network Security

1. **Azure NSGs**: Restrict traffic to/from APIM and AKS
2. **AWS Security Groups**: Control EKS node and LoadBalancer access
3. **Kubernetes Network Policies**: (Optional) Fine-grained pod-to-pod restrictions

### Secrets Management

- Gateway token stored in Kubernetes Secret
- ACR/ECR credentials managed via IAM/managed identity

## Scalability

### Horizontal Scaling

| Component | Min | Max | Scaling Trigger |
|-----------|-----|-----|-----------------|
| AKS API Pods | 2 | 10 | CPU > 70% |
| EKS API Pods | 2 | 10 | CPU > 70% |
| Self-Hosted GW | 2 | 5 | Manual |

### Vertical Scaling

- APIM: Upgrade SKU (Developer → Basic → Standard → Premium)
- AKS/EKS: Increase node instance sizes

## Monitoring

### Recommended Metrics

1. **APIM Metrics**:
   - Request count by API
   - Response time percentiles
   - Error rates

2. **Self-Hosted Gateway**:
   - Configuration sync status
   - Request throughput
   - Connection to APIM status

3. **Kubernetes**:
   - Pod health and restarts
   - Resource utilization
   - Service availability

## Cost Optimization

### Development Environment

- APIM Developer SKU (~$50/month)
- AKS: 2x Standard_DS2_v2 (~$140/month)
- EKS: 2x t3.medium (~$60/month)
- **Total**: ~$250/month

### Production Considerations

- APIM Premium required for self-hosted gateway in production
- Consider reserved instances for cost savings
- Implement auto-scaling to match demand
