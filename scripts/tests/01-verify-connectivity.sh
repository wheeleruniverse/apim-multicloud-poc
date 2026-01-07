#!/bin/bash
# 01-verify-connectivity.sh
# Verifies basic connectivity to all API endpoints through APIM and directly

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common utilities if available
if [[ -f "${SCRIPT_DIR}/../utilities/common.sh" ]]; then
    source "${SCRIPT_DIR}/../utilities/common.sh"
else
    # Fallback definitions
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
    
    log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
    log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
    log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
    print_banner() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}========================================${NC}\n"; }
fi

# Configuration
APIM_GATEWAY_URL="${APIM_GATEWAY_URL:-}"
SELF_HOSTED_GW_URL="${SELF_HOSTED_GW_URL:-}"
AKS_DIRECT_URL="${AKS_DIRECT_URL:-}"
EKS_DIRECT_URL="${EKS_DIRECT_URL:-}"

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
RESULTS=()

print_banner "APIM Multi-Cloud Connectivity Verification"

print_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --apim-url URL        Azure APIM Gateway URL (required)"
    echo "  --shgw-url URL        Self-Hosted Gateway URL in AWS (required)"
    echo "  --aks-url URL         AKS Direct URL (optional, for comparison)"
    echo "  --eks-url URL         EKS Direct URL (optional, for comparison)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  APIM_GATEWAY_URL      Alternative to --apim-url"
    echo "  SELF_HOSTED_GW_URL    Alternative to --shgw-url"
    echo ""
    echo "Examples:"
    echo "  $0 --apim-url https://myapim.azure-api.net --shgw-url http://gateway.example.com"
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
        --aks-url)
            AKS_DIRECT_URL="$2"
            shift 2
            ;;
        --eks-url)
            EKS_DIRECT_URL="$2"
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
if [[ -z "$APIM_GATEWAY_URL" ]]; then
    log_error "APIM Gateway URL is required"
    print_usage
    exit 1
fi

if [[ -z "$SELF_HOSTED_GW_URL" ]]; then
    log_error "Self-Hosted Gateway URL is required"
    print_usage
    exit 1
fi

# Test function
test_endpoint() {
    local name="$1"
    local url="$2"
    local expected_source="$3"
    
    echo -n "Testing: $name... "
    
    local response
    local http_code
    
    # Make request and capture response
    response=$(curl -s -w "\n%{http_code}" --connect-timeout 10 --max-time 30 "$url" 2>/dev/null) || {
        echo -e "${RED}FAILED${NC} (connection error)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        RESULTS+=("FAIL: $name - Connection error")
        return 1
    }
    
    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" != "200" ]]; then
        echo -e "${RED}FAILED${NC} (HTTP $http_code)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        RESULTS+=("FAIL: $name - HTTP $http_code")
        return 1
    fi
    
    # Parse JSON response
    local source
    source=$(echo "$body" | grep -o '"source"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    local message
    message=$(echo "$body" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    
    if [[ -n "$expected_source" && "$source" != "$expected_source" ]]; then
        echo -e "${YELLOW}WARNING${NC} (expected source: $expected_source, got: $source)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        RESULTS+=("WARN: $name - Source mismatch (expected: $expected_source, got: $source)")
        return 0
    fi
    
    echo -e "${GREEN}PASSED${NC} - $message"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    RESULTS+=("PASS: $name - $message")
    return 0
}

# Test health endpoint
test_health() {
    local name="$1"
    local url="$2"
    
    echo -n "Health Check: $name... "
    
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 "$url" 2>/dev/null) || {
        echo -e "${RED}FAILED${NC} (connection error)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    }
    
    if [[ "$http_code" == "200" ]]; then
        echo -e "${GREEN}HEALTHY${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}UNHEALTHY${NC} (HTTP $http_code)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Print configuration
echo "Configuration:"
echo "  APIM Gateway URL:      $APIM_GATEWAY_URL"
echo "  Self-Hosted GW URL:    $SELF_HOSTED_GW_URL"
[[ -n "$AKS_DIRECT_URL" ]] && echo "  AKS Direct URL:        $AKS_DIRECT_URL"
[[ -n "$EKS_DIRECT_URL" ]] && echo "  EKS Direct URL:        $EKS_DIRECT_URL"
echo ""

# Run tests
echo "=========================================="
echo "Running Connectivity Tests"
echo "=========================================="
echo ""

# Test 1: Azure API via APIM
test_endpoint "Azure API via APIM" "${APIM_GATEWAY_URL}/azure-api/hello" "Azure"

# Test 2: AWS API via APIM (routes through self-hosted gateway)
test_endpoint "AWS API via APIM" "${APIM_GATEWAY_URL}/aws-api/hello" "AWS"

# Test 3: AWS API via Self-Hosted Gateway directly
test_endpoint "AWS API via Self-Hosted GW" "${SELF_HOSTED_GW_URL}/aws-api/hello" "AWS"

# Test 4: Health endpoints
echo ""
echo "Health Checks:"
test_health "Azure API Health (APIM)" "${APIM_GATEWAY_URL}/azure-api/health"
test_health "AWS API Health (SHGW)" "${SELF_HOSTED_GW_URL}/aws-api/health"

# Optional direct cluster tests
if [[ -n "$AKS_DIRECT_URL" ]]; then
    echo ""
    echo "Direct Cluster Access (AKS):"
    test_endpoint "Azure API Direct" "${AKS_DIRECT_URL}/hello" "Azure"
fi

if [[ -n "$EKS_DIRECT_URL" ]]; then
    echo ""
    echo "Direct Cluster Access (EKS):"
    test_endpoint "AWS API Direct" "${EKS_DIRECT_URL}/hello" "AWS"
fi

# Print summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"
echo ""

echo "Detailed Results:"
for result in "${RESULTS[@]}"; do
    if [[ "$result" == PASS:* ]]; then
        echo -e "  ${GREEN}✓${NC} ${result#PASS: }"
    elif [[ "$result" == WARN:* ]]; then
        echo -e "  ${YELLOW}⚠${NC} ${result#WARN: }"
    else
        echo -e "  ${RED}✗${NC} ${result#FAIL: }"
    fi
done

echo ""

if [[ $TESTS_FAILED -gt 0 ]]; then
    log_error "Some tests failed!"
    exit 1
else
    log_success "All connectivity tests passed!"
    exit 0
fi
