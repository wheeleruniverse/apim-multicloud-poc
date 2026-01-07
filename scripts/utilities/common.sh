#!/bin/bash
# common.sh - Common utilities for APIM Multi-Cloud POC scripts

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export MAGENTA='\033[0;35m'
export NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

log_test() {
    echo -e "${MAGENTA}[TEST]${NC} $1"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

# Print a banner
print_banner() {
    local text="$1"
    local width=50
    local padding=$(( (width - ${#text}) / 2 ))
    
    echo ""
    echo -e "${BLUE}$(printf '=%.0s' $(seq 1 $width))${NC}"
    printf "${BLUE}%*s%s%*s${NC}\n" $padding "" "$text" $padding ""
    echo -e "${BLUE}$(printf '=%.0s' $(seq 1 $width))${NC}"
    echo ""
}

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Check required commands
check_requirements() {
    local missing=()
    
    for cmd in "$@"; do
        if ! command_exists "$cmd"; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        return 1
    fi
    
    return 0
}

# Make HTTP request and return response code
http_get() {
    local url="$1"
    local timeout="${2:-10}"
    
    curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout "$timeout" \
        --max-time "$((timeout * 2))" \
        "$url" 2>/dev/null || echo "000"
}

# Make HTTP request and return full response
http_get_full() {
    local url="$1"
    local timeout="${2:-10}"
    
    curl -s \
        --connect-timeout "$timeout" \
        --max-time "$((timeout * 2))" \
        "$url" 2>/dev/null
}

# Wait for URL to be available
wait_for_url() {
    local url="$1"
    local timeout="${2:-120}"
    local interval="${3:-5}"
    local expected_code="${4:-200}"
    
    log_info "Waiting for $url to be available..."
    
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        local code
        code=$(http_get "$url" 5)
        
        if [[ "$code" == "$expected_code" ]]; then
            log_success "URL is available (HTTP $code)"
            return 0
        fi
        
        log_debug "Got HTTP $code, waiting..."
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    
    log_error "Timeout waiting for $url (last code: $code)"
    return 1
}

# Wait for Kubernetes deployment to be ready
wait_for_deployment() {
    local namespace="$1"
    local deployment="$2"
    local timeout="${3:-300}"
    local kubectl_cmd="${4:-kubectl}"
    
    log_info "Waiting for deployment $deployment in namespace $namespace..."
    
    if $kubectl_cmd rollout status deployment/"$deployment" \
        -n "$namespace" \
        --timeout="${timeout}s"; then
        log_success "Deployment is ready"
        return 0
    else
        log_error "Deployment rollout failed or timed out"
        return 1
    fi
}

# Get the external IP/hostname of a LoadBalancer service
get_lb_address() {
    local namespace="$1"
    local service="$2"
    local timeout="${3:-300}"
    local kubectl_cmd="${4:-kubectl}"
    
    log_info "Getting LoadBalancer address for $service..."
    
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        local address
        
        # Try hostname first (AWS NLB)
        address=$($kubectl_cmd get svc "$service" -n "$namespace" \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
        
        # If no hostname, try IP (Azure, GCP)
        if [[ -z "$address" ]]; then
            address=$($kubectl_cmd get svc "$service" -n "$namespace" \
                -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        fi
        
        if [[ -n "$address" && "$address" != "null" ]]; then
            echo "$address"
            return 0
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    log_error "Timeout waiting for LoadBalancer address"
    return 1
}

# Parse JSON field
json_get() {
    local json="$1"
    local field="$2"
    
    echo "$json" | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | \
        cut -d'"' -f4
}

# Validate URL format
validate_url() {
    local url="$1"
    
    if [[ "$url" =~ ^https?:// ]]; then
        return 0
    else
        return 1
    fi
}

# Generate timestamp
timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Generate unique ID
generate_id() {
    echo "$(date +%s)-$(head /dev/urandom | tr -dc a-z0-9 | head -c 8)"
}

# Confirm action with user
confirm() {
    local message="${1:-Are you sure?}"
    local default="${2:-n}"
    
    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi
    
    read -r -p "$message $prompt " response
    response=${response:-$default}
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Cleanup trap helper
setup_cleanup() {
    local cleanup_function="$1"
    trap "$cleanup_function" EXIT INT TERM
}

# Export all functions
export -f log_info log_warn log_error log_success log_step log_test log_debug
export -f print_banner command_exists check_requirements
export -f http_get http_get_full wait_for_url
export -f wait_for_deployment get_lb_address
export -f json_get validate_url timestamp generate_id
export -f confirm setup_cleanup
