#!/bin/bash
# get-endpoints.sh - Retrieve all endpoint URLs from deployed infrastructure

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

print_banner "APIM Multi-Cloud Endpoint Discovery"

# Configuration
TERRAFORM_DIR="${TERRAFORM_DIR:-../../terraform/environments/dev}"
EKS_CONTEXT="${EKS_CONTEXT:-}"
AKS_CONTEXT="${AKS_CONTEXT:-}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-apim-gateway}"
API_NAMESPACE="${API_NAMESPACE:-hello-api}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-env}"  # env, json, or shell

print_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --terraform-dir DIR   Path to Terraform environment directory"
    echo "  --eks-context CTX     kubectl context for EKS"
    echo "  --aks-context CTX     kubectl context for AKS"
    echo "  --format FORMAT       Output format: env, json, shell (default: env)"
    echo "  -h, --help            Show this help message"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --terraform-dir)
            TERRAFORM_DIR="$2"
            shift 2
            ;;
        --eks-context)
            EKS_CONTEXT="$2"
            shift 2
            ;;
        --aks-context)
            AKS_CONTEXT="$2"
            shift 2
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# kubectl commands
EKS_KUBECTL="kubectl"
AKS_KUBECTL="kubectl"
[[ -n "$EKS_CONTEXT" ]] && EKS_KUBECTL="kubectl --context=$EKS_CONTEXT"
[[ -n "$AKS_CONTEXT" ]] && AKS_KUBECTL="kubectl --context=$AKS_CONTEXT"

# Collect endpoints
declare -A ENDPOINTS

# Try to get APIM URL from Terraform
if [[ -d "$TERRAFORM_DIR" ]]; then
    log_info "Reading Terraform outputs..."
    cd "$TERRAFORM_DIR"
    
    if terraform output &>/dev/null; then
        APIM_URL=$(terraform output -raw azure_apim_gateway_url 2>/dev/null || echo "")
        ENDPOINTS["APIM_GATEWAY_URL"]="$APIM_URL"
    fi
    cd - > /dev/null
fi

# Get Self-Hosted Gateway URL from EKS
log_info "Getting Self-Hosted Gateway URL from EKS..."
SHGW_HOST=$($EKS_KUBECTL get svc apim-gateway -n "$GATEWAY_NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
    $EKS_KUBECTL get svc apim-gateway -n "$GATEWAY_NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [[ -n "$SHGW_HOST" ]]; then
    ENDPOINTS["SELF_HOSTED_GW_URL"]="http://${SHGW_HOST}"
fi

# Get AKS direct URL (optional)
log_info "Getting AKS direct URL..."
AKS_HOST=$($AKS_KUBECTL get svc hello-api-external -n "$API_NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [[ -n "$AKS_HOST" ]]; then
    ENDPOINTS["AKS_DIRECT_URL"]="http://${AKS_HOST}"
fi

# Get EKS direct URL (optional)
log_info "Getting EKS direct URL..."
EKS_HOST=$($EKS_KUBECTL get svc hello-api-external -n "$API_NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
    $EKS_KUBECTL get svc hello-api-external -n "$API_NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [[ -n "$EKS_HOST" ]]; then
    ENDPOINTS["EKS_DIRECT_URL"]="http://${EKS_HOST}"
fi

# Output results
echo ""
case "$OUTPUT_FORMAT" in
    env)
        echo "# APIM Multi-Cloud Endpoints"
        echo "# Add these to your environment or .env file"
        echo ""
        for key in "${!ENDPOINTS[@]}"; do
            echo "export ${key}=\"${ENDPOINTS[$key]}\""
        done
        ;;
    json)
        echo "{"
        first=true
        for key in "${!ENDPOINTS[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            echo -n "  \"$key\": \"${ENDPOINTS[$key]}\""
        done
        echo ""
        echo "}"
        ;;
    shell)
        echo "# Run this in your shell to set environment variables:"
        echo ""
        for key in "${!ENDPOINTS[@]}"; do
            echo "${key}=\"${ENDPOINTS[$key]}\""
        done
        ;;
esac

echo ""
log_success "Endpoint discovery complete"

# Print test commands
if [[ "$OUTPUT_FORMAT" == "env" ]]; then
    echo ""
    echo "# Quick test commands:"
    echo "# curl \"\${APIM_GATEWAY_URL}/azure-api/hello\""
    echo "# curl \"\${APIM_GATEWAY_URL}/aws-api/hello\""
    echo "# curl \"\${SELF_HOSTED_GW_URL}/aws-api/hello\""
fi
