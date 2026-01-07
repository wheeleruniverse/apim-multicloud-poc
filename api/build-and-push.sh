#!/bin/bash
# Build and push Hello API container to both Azure ACR and AWS ECR

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration - Update these values based on your Terraform outputs
ACR_NAME="${ACR_NAME:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REPO="${ECR_REPO:-}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

print_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --acr-name NAME      Azure Container Registry name"
    echo "  --ecr-repo URL       AWS ECR repository URL"
    echo "  --aws-region REGION  AWS region (default: us-east-1)"
    echo "  --tag TAG            Image tag (default: latest)"
    echo "  --azure-only         Build and push to Azure ACR only"
    echo "  --aws-only           Build and push to AWS ECR only"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --acr-name myacr --ecr-repo 123456789.dkr.ecr.us-east-1.amazonaws.com/my-repo"
    echo "  $0 --azure-only --acr-name myacr --tag v1.0.0"
}

# Parse arguments
AZURE_ONLY=false
AWS_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --acr-name)
            ACR_NAME="$2"
            shift 2
            ;;
        --ecr-repo)
            ECR_REPO="$2"
            shift 2
            ;;
        --aws-region)
            AWS_REGION="$2"
            shift 2
            ;;
        --tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --azure-only)
            AZURE_ONLY=true
            shift
            ;;
        --aws-only)
            AWS_ONLY=true
            shift
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

# Validate inputs
if [[ "$AZURE_ONLY" == "false" && -z "$ECR_REPO" ]]; then
    log_error "ECR repository URL is required (use --ecr-repo or --azure-only)"
    exit 1
fi

if [[ "$AWS_ONLY" == "false" && -z "$ACR_NAME" ]]; then
    log_error "ACR name is required (use --acr-name or --aws-only)"
    exit 1
fi

# Build the Docker image
log_info "Building Docker image..."
cd "${PROJECT_ROOT}"
docker build -t hello-api:${IMAGE_TAG} -f docker/Dockerfile .

# Push to Azure ACR
if [[ "$AWS_ONLY" == "false" ]]; then
    log_info "Logging into Azure Container Registry: ${ACR_NAME}..."
    az acr login --name "${ACR_NAME}"
    
    ACR_URL="${ACR_NAME}.azurecr.io"
    AZURE_IMAGE="${ACR_URL}/hello-api:${IMAGE_TAG}"
    
    log_info "Tagging image for Azure ACR..."
    docker tag hello-api:${IMAGE_TAG} "${AZURE_IMAGE}"
    
    log_info "Pushing image to Azure ACR..."
    docker push "${AZURE_IMAGE}"
    
    log_info "Successfully pushed to Azure ACR: ${AZURE_IMAGE}"
fi

# Push to AWS ECR
if [[ "$AZURE_ONLY" == "false" ]]; then
    log_info "Logging into AWS ECR..."
    aws ecr get-login-password --region "${AWS_REGION}" | \
        docker login --username AWS --password-stdin "${ECR_REPO%%/*}"
    
    AWS_IMAGE="${ECR_REPO}:${IMAGE_TAG}"
    
    log_info "Tagging image for AWS ECR..."
    docker tag hello-api:${IMAGE_TAG} "${AWS_IMAGE}"
    
    log_info "Pushing image to AWS ECR..."
    docker push "${AWS_IMAGE}"
    
    log_info "Successfully pushed to AWS ECR: ${AWS_IMAGE}"
fi

log_info "Build and push complete!"
echo ""
echo "Images:"
if [[ "$AWS_ONLY" == "false" ]]; then
    echo "  Azure: ${ACR_NAME}.azurecr.io/hello-api:${IMAGE_TAG}"
fi
if [[ "$AZURE_ONLY" == "false" ]]; then
    echo "  AWS:   ${ECR_REPO}:${IMAGE_TAG}"
fi
