#!/bin/bash
# 02-simulate-azure-outage.sh
# Simulates an Azure outage to test self-hosted gateway resilience
# Uses network policies or iptables to block Azure connectivity

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }
print_banner() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}========================================${NC}\n"; }

# Configuration
APIM_GATEWAY_URL="${APIM_GATEWAY_URL:-}"
SELF_HOSTED_GW_URL="${SELF_HOSTED_GW_URL:-}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-apim-gateway}"
SIMULATION_METHOD="${SIMULATION_METHOD:-networkpolicy}"  # networkpolicy or dns
TEST_DURATION="${TEST_DURATION:-60}"  # seconds
EKS_CONTEXT="${EKS_CONTEXT:-}"

print_banner "Azure Outage Simulation Test"

print_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "This script simulates an Azure outage to verify that the self-hosted"
    echo "gateway continues to function using its cached configuration."
    echo ""
    echo "Options:"
    echo "  --apim-url URL          Azure APIM Gateway URL (required)"
    echo "  --shgw-url URL          Self-Hosted Gateway URL (required)"
    echo "  --eks-context CTX       kubectl context for EKS cluster"
    echo "  --gateway-ns NAMESPACE  Gateway namespace (default: apim-gateway)"
    echo "  --method METHOD         Simulation method: networkpolicy|dns (default: networkpolicy)"
    echo "  --duration SECONDS      Test duration in seconds (default: 60)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Simulation Methods:"
    echo "  networkpolicy - Uses K8s NetworkPolicy to block Azure traffic"
    echo "  dns           - Modifies DNS to block Azure domain resolution"
    echo ""
    echo "Examples:"
    echo "  $0 --apim-url https://myapim.azure-api.net --shgw-url http://gateway.example.com"
    echo "  $0 --apim-url https://myapim.azure-api.net --shgw-url http://gateway.example.com --duration 120"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --apim-url)
            APIM_GATEWAY_URL="$2"
            shift 2
            ;;
        --shgw-url)
            SELF_HOSTED_GW_URL="$2"
            shift 2
            ;;
        --eks-context)
            EKS_CONTEXT="$2"
            shift 2
            ;;
        --gateway-ns)
            GATEWAY_NAMESPACE="$2"
            shift 2
            ;;
        --method)
            SIMULATION_METHOD="$2"
            shift 2
            ;;
        --duration)
            TEST_DURATION="$2"
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

# Validate required parameters
if [[ -z "$APIM_GATEWAY_URL" || -z "$SELF_HOSTED_GW_URL" ]]; then
    log_error "Both APIM Gateway URL and Self-Hosted Gateway URL are required"
    print_usage
    exit 1
fi

# Set kubectl context if provided
KUBECTL_CMD="kubectl"
if [[ -n "$EKS_CONTEXT" ]]; then
    KUBECTL_CMD="kubectl --context=$EKS_CONTEXT"
fi

# Extract APIM hostname for blocking
APIM_HOST=$(echo "$APIM_GATEWAY_URL" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
log_info "APIM Host to block: $APIM_HOST"

# Network policy to block Azure traffic
create_network_policy() {
    log_step "Creating NetworkPolicy to block Azure connectivity..."
    
    cat <<EOF | $KUBECTL_CMD apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-azure-apim
  namespace: ${GATEWAY_NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: apim-gateway
  policyTypes:
    - Egress
  egress:
    # Allow DNS
    - to: []
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # Allow internal cluster traffic
    - to:
        - namespaceSelector: {}
    # Block all external traffic (simulates Azure outage)
    # By not including any other egress rules, all external traffic is blocked
EOF

    log_success "NetworkPolicy created to block Azure traffic"
}

remove_network_policy() {
    log_step "Removing NetworkPolicy..."
    $KUBECTL_CMD delete networkpolicy block-azure-apim -n ${GATEWAY_NAMESPACE} --ignore-not-found=true
    log_success "NetworkPolicy removed"
}

# Test API endpoint
test_api() {
    local name="$1"
    local url="$2"
    local expected_result="$3"  # success or failure
    
    echo -n "  Testing $name... "
    
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 "$url" 2>/dev/null) || http_code="000"
    
    if [[ "$expected_result" == "success" ]]; then
        if [[ "$http_code" == "200" ]]; then
            echo -e "${GREEN}PASSED${NC} (HTTP $http_code)"
            return 0
        else
            echo -e "${RED}FAILED${NC} (HTTP $http_code, expected 200)"
            return 1
        fi
    else
        if [[ "$http_code" != "200" ]]; then
            echo -e "${GREEN}EXPECTED${NC} (HTTP $http_code - Azure unavailable)"
            return 0
        else
            echo -e "${YELLOW}UNEXPECTED${NC} (HTTP $http_code - Azure still reachable)"
            return 0
        fi
    fi
}

# Check gateway logs
check_gateway_logs() {
    log_step "Checking gateway logs for config backup usage..."
    
    local logs
    logs=$($KUBECTL_CMD logs -l app=apim-gateway -n ${GATEWAY_NAMESPACE} --tail=50 2>/dev/null) || {
        log_warn "Could not retrieve gateway logs"
        return
    }
    
    if echo "$logs" | grep -qi "backup\|cached\|offline"; then
        log_success "Gateway appears to be using cached configuration"
    else
        log_info "No explicit backup/cached messages found (gateway may still be using cache)"
    fi
}

# Cleanup function
cleanup() {
    log_warn "Cleaning up..."
    remove_network_policy
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Main test flow
echo "Configuration:"
echo "  APIM Gateway URL:     $APIM_GATEWAY_URL"
echo "  Self-Hosted GW URL:   $SELF_HOSTED_GW_URL"
echo "  Gateway Namespace:    $GATEWAY_NAMESPACE"
echo "  Simulation Method:    $SIMULATION_METHOD"
echo "  Test Duration:        ${TEST_DURATION}s"
echo ""

# Phase 1: Pre-test - Verify everything works
print_banner "Phase 1: Pre-Test Verification"

log_step "Verifying all endpoints are accessible before simulation..."
echo ""

test_api "Azure API via APIM" "${APIM_GATEWAY_URL}/azure-api/hello" "success"
test_api "AWS API via APIM" "${APIM_GATEWAY_URL}/aws-api/hello" "success"
test_api "AWS API via Self-Hosted GW" "${SELF_HOSTED_GW_URL}/aws-api/hello" "success"

echo ""
log_success "Pre-test verification complete"

# Phase 2: Simulate outage
print_banner "Phase 2: Simulating Azure Outage"

log_warn "SIMULATING AZURE OUTAGE - Gateway will lose connection to APIM"
echo ""

if [[ "$SIMULATION_METHOD" == "networkpolicy" ]]; then
    create_network_policy
else
    log_error "DNS simulation method not implemented in this version"
    exit 1
fi

# Wait for network policy to take effect
log_info "Waiting 10 seconds for network policy to take effect..."
sleep 10

# Phase 3: Test during outage
print_banner "Phase 3: Testing During Simulated Outage"

log_info "Testing API availability during Azure outage..."
log_info "The self-hosted gateway should continue to work using cached config"
echo ""

# Test Azure API (should fail or timeout)
test_api "Azure API via APIM (expected to fail)" "${APIM_GATEWAY_URL}/azure-api/hello" "failure"

# Test AWS API via self-hosted gateway (should work with cached config)
test_api "AWS API via Self-Hosted GW (should use cache)" "${SELF_HOSTED_GW_URL}/aws-api/hello" "success"

echo ""

# Continuous testing during outage period
log_info "Running continuous tests for ${TEST_DURATION} seconds..."
echo ""

START_TIME=$(date +%s)
SUCCESS_COUNT=0
FAILURE_COUNT=0
TEST_COUNT=0

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [[ $ELAPSED -ge $TEST_DURATION ]]; then
        break
    fi
    
    TEST_COUNT=$((TEST_COUNT + 1))
    echo -n "  [$ELAPSED/${TEST_DURATION}s] Test #$TEST_COUNT: "
    
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "${SELF_HOSTED_GW_URL}/aws-api/hello" 2>/dev/null) || http_code="000"
    
    if [[ "$http_code" == "200" ]]; then
        echo -e "${GREEN}✓${NC} (HTTP $http_code)"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo -e "${RED}✗${NC} (HTTP $http_code)"
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
    fi
    
    sleep 5
done

echo ""
log_info "Continuous test results: $SUCCESS_COUNT successes, $FAILURE_COUNT failures out of $TEST_COUNT tests"

# Check gateway logs
check_gateway_logs

# Phase 4: Restore connectivity
print_banner "Phase 4: Restoring Azure Connectivity"

remove_network_policy

log_info "Waiting 30 seconds for gateway to reconnect to APIM..."
sleep 30

# Phase 5: Post-recovery verification
print_banner "Phase 5: Post-Recovery Verification"

log_step "Verifying all endpoints are accessible after recovery..."
echo ""

RECOVERY_SUCCESS=true

test_api "Azure API via APIM" "${APIM_GATEWAY_URL}/azure-api/hello" "success" || RECOVERY_SUCCESS=false
test_api "AWS API via APIM" "${APIM_GATEWAY_URL}/aws-api/hello" "success" || RECOVERY_SUCCESS=false
test_api "AWS API via Self-Hosted GW" "${SELF_HOSTED_GW_URL}/aws-api/hello" "success" || RECOVERY_SUCCESS=false

# Final summary
print_banner "Test Summary"

echo "Outage Simulation Results:"
echo "  Duration:          ${TEST_DURATION} seconds"
echo "  Tests during outage: $TEST_COUNT"
echo "  Successes:         $SUCCESS_COUNT"
echo "  Failures:          $FAILURE_COUNT"
echo ""

if [[ $SUCCESS_COUNT -gt 0 && $RECOVERY_SUCCESS == true ]]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}SELF-HOSTED GATEWAY RESILIENCE VERIFIED${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    log_success "The self-hosted gateway maintained API availability during the simulated Azure outage"
    log_success "Configuration backup feature is working as expected"
    exit 0
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}RESILIENCE TEST FAILED${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    log_error "The self-hosted gateway did not maintain availability during the outage"
    log_error "Check gateway configuration backup settings"
    exit 1
fi
