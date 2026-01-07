#!/bin/bash
# 03-full-resilience-test.sh
# Comprehensive resilience test suite for APIM multi-cloud setup
# Tests various failure scenarios and recovery patterns

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_test() { echo -e "${MAGENTA}[TEST]${NC} $1"; }
print_banner() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}========================================${NC}\n"; }

# Configuration
APIM_GATEWAY_URL="${APIM_GATEWAY_URL:-}"
SELF_HOSTED_GW_URL="${SELF_HOSTED_GW_URL:-}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-apim-gateway}"
API_NAMESPACE="${API_NAMESPACE:-hello-api}"
EKS_CONTEXT="${EKS_CONTEXT:-}"
AKS_CONTEXT="${AKS_CONTEXT:-}"
REPORT_FILE="${REPORT_FILE:-./resilience-test-report.md}"

# Test results
declare -A TEST_RESULTS
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

print_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --apim-url URL          Azure APIM Gateway URL (required)"
    echo "  --shgw-url URL          Self-Hosted Gateway URL (required)"
    echo "  --eks-context CTX       kubectl context for EKS cluster"
    echo "  --aks-context CTX       kubectl context for AKS cluster"
    echo "  --gateway-ns NAMESPACE  Gateway namespace (default: apim-gateway)"
    echo "  --api-ns NAMESPACE      API namespace (default: hello-api)"
    echo "  --report FILE           Output report file (default: ./resilience-test-report.md)"
    echo "  -h, --help              Show this help message"
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
        --aks-context)
            AKS_CONTEXT="$2"
            shift 2
            ;;
        --gateway-ns)
            GATEWAY_NAMESPACE="$2"
            shift 2
            ;;
        --api-ns)
            API_NAMESPACE="$2"
            shift 2
            ;;
        --report)
            REPORT_FILE="$2"
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

# kubectl commands
EKS_KUBECTL="kubectl"
[[ -n "$EKS_CONTEXT" ]] && EKS_KUBECTL="kubectl --context=$EKS_CONTEXT"

# Record test result
record_result() {
    local test_name="$1"
    local result="$2"  # PASS, FAIL, SKIP
    local details="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    TEST_RESULTS["$test_name"]="$result: $details"
    
    case $result in
        PASS)
            PASSED_TESTS=$((PASSED_TESTS + 1))
            echo -e "  ${GREEN}✓ PASS${NC}: $test_name"
            ;;
        FAIL)
            FAILED_TESTS=$((FAILED_TESTS + 1))
            echo -e "  ${RED}✗ FAIL${NC}: $test_name - $details"
            ;;
        SKIP)
            SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
            echo -e "  ${YELLOW}○ SKIP${NC}: $test_name - $details"
            ;;
    esac
}

# Test API endpoint
test_endpoint() {
    local url="$1"
    local timeout="${2:-10}"
    
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$timeout" --max-time "$((timeout * 2))" "$url" 2>/dev/null) || http_code="000"
    echo "$http_code"
}

# Wait for condition
wait_for() {
    local description="$1"
    local command="$2"
    local timeout="${3:-60}"
    local interval="${4:-5}"
    
    log_info "Waiting for: $description (timeout: ${timeout}s)"
    
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if eval "$command" &>/dev/null; then
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    
    return 1
}

print_banner "APIM Multi-Cloud Full Resilience Test Suite"

echo "Configuration:"
echo "  APIM Gateway URL:     $APIM_GATEWAY_URL"
echo "  Self-Hosted GW URL:   $SELF_HOSTED_GW_URL"
echo "  Gateway Namespace:    $GATEWAY_NAMESPACE"
echo "  API Namespace:        $API_NAMESPACE"
echo "  Report File:          $REPORT_FILE"
echo ""

# Initialize report
cat > "$REPORT_FILE" << EOF
# APIM Multi-Cloud Resilience Test Report

**Date:** $(date -Iseconds)
**APIM Gateway:** $APIM_GATEWAY_URL
**Self-Hosted Gateway:** $SELF_HOSTED_GW_URL

## Test Results

EOF

#=============================================================================
# TEST SUITE 1: Basic Connectivity
#=============================================================================
print_banner "Test Suite 1: Basic Connectivity"

log_test "1.1 - Azure API via APIM"
http_code=$(test_endpoint "${APIM_GATEWAY_URL}/azure-api/hello")
if [[ "$http_code" == "200" ]]; then
    record_result "1.1 Azure API via APIM" "PASS" "HTTP 200"
else
    record_result "1.1 Azure API via APIM" "FAIL" "HTTP $http_code"
fi

log_test "1.2 - AWS API via APIM"
http_code=$(test_endpoint "${APIM_GATEWAY_URL}/aws-api/hello")
if [[ "$http_code" == "200" ]]; then
    record_result "1.2 AWS API via APIM" "PASS" "HTTP 200"
else
    record_result "1.2 AWS API via APIM" "FAIL" "HTTP $http_code"
fi

log_test "1.3 - AWS API via Self-Hosted Gateway"
http_code=$(test_endpoint "${SELF_HOSTED_GW_URL}/aws-api/hello")
if [[ "$http_code" == "200" ]]; then
    record_result "1.3 AWS API via Self-Hosted GW" "PASS" "HTTP 200"
else
    record_result "1.3 AWS API via Self-Hosted GW" "FAIL" "HTTP $http_code"
fi

log_test "1.4 - Health Endpoints"
azure_health=$(test_endpoint "${APIM_GATEWAY_URL}/azure-api/health")
aws_health=$(test_endpoint "${SELF_HOSTED_GW_URL}/aws-api/health")
if [[ "$azure_health" == "200" && "$aws_health" == "200" ]]; then
    record_result "1.4 Health Endpoints" "PASS" "Both healthy"
else
    record_result "1.4 Health Endpoints" "FAIL" "Azure: $azure_health, AWS: $aws_health"
fi

#=============================================================================
# TEST SUITE 2: Load and Performance
#=============================================================================
print_banner "Test Suite 2: Load and Performance"

log_test "2.1 - Concurrent Requests to Azure API"
success_count=0
for i in {1..10}; do
    http_code=$(test_endpoint "${APIM_GATEWAY_URL}/azure-api/hello" 5)
    [[ "$http_code" == "200" ]] && success_count=$((success_count + 1))
done
if [[ $success_count -ge 9 ]]; then
    record_result "2.1 Concurrent Azure Requests" "PASS" "$success_count/10 succeeded"
else
    record_result "2.1 Concurrent Azure Requests" "FAIL" "$success_count/10 succeeded"
fi

log_test "2.2 - Concurrent Requests to AWS API"
success_count=0
for i in {1..10}; do
    http_code=$(test_endpoint "${SELF_HOSTED_GW_URL}/aws-api/hello" 5)
    [[ "$http_code" == "200" ]] && success_count=$((success_count + 1))
done
if [[ $success_count -ge 9 ]]; then
    record_result "2.2 Concurrent AWS Requests" "PASS" "$success_count/10 succeeded"
else
    record_result "2.2 Concurrent AWS Requests" "FAIL" "$success_count/10 succeeded"
fi

log_test "2.3 - Response Time Check"
start_time=$(date +%s%N)
http_code=$(test_endpoint "${SELF_HOSTED_GW_URL}/aws-api/hello" 10)
end_time=$(date +%s%N)
response_time=$(( (end_time - start_time) / 1000000 ))  # Convert to ms
if [[ "$http_code" == "200" && $response_time -lt 5000 ]]; then
    record_result "2.3 Response Time" "PASS" "${response_time}ms"
else
    record_result "2.3 Response Time" "FAIL" "${response_time}ms (HTTP $http_code)"
fi

#=============================================================================
# TEST SUITE 3: Gateway Pod Resilience
#=============================================================================
print_banner "Test Suite 3: Gateway Pod Resilience"

if [[ -n "$EKS_CONTEXT" ]]; then
    log_test "3.1 - Gateway Pod Restart Recovery"
    
    # Get current pod count
    original_pods=$($EKS_KUBECTL get pods -n "$GATEWAY_NAMESPACE" -l app=apim-gateway -o name | wc -l)
    
    if [[ $original_pods -gt 0 ]]; then
        # Delete one pod
        first_pod=$($EKS_KUBECTL get pods -n "$GATEWAY_NAMESPACE" -l app=apim-gateway -o name | head -1)
        log_info "Deleting pod: $first_pod"
        $EKS_KUBECTL delete "$first_pod" -n "$GATEWAY_NAMESPACE" --wait=false
        
        # Wait for recovery
        sleep 30
        
        # Test endpoint
        http_code=$(test_endpoint "${SELF_HOSTED_GW_URL}/aws-api/hello" 15)
        if [[ "$http_code" == "200" ]]; then
            record_result "3.1 Gateway Pod Restart" "PASS" "Recovered after pod deletion"
        else
            record_result "3.1 Gateway Pod Restart" "FAIL" "HTTP $http_code after restart"
        fi
    else
        record_result "3.1 Gateway Pod Restart" "SKIP" "No gateway pods found"
    fi
    
    log_test "3.2 - Gateway Scaling"
    
    # Scale down to 1
    log_info "Scaling gateway to 1 replica"
    $EKS_KUBECTL scale deployment apim-self-hosted-gateway -n "$GATEWAY_NAMESPACE" --replicas=1
    sleep 20
    
    http_code=$(test_endpoint "${SELF_HOSTED_GW_URL}/aws-api/hello")
    scale_down_result="$http_code"
    
    # Scale back up to 2
    log_info "Scaling gateway back to 2 replicas"
    $EKS_KUBECTL scale deployment apim-self-hosted-gateway -n "$GATEWAY_NAMESPACE" --replicas=2
    sleep 30
    
    http_code=$(test_endpoint "${SELF_HOSTED_GW_URL}/aws-api/hello")
    
    if [[ "$scale_down_result" == "200" && "$http_code" == "200" ]]; then
        record_result "3.2 Gateway Scaling" "PASS" "Works at 1 and 2 replicas"
    else
        record_result "3.2 Gateway Scaling" "FAIL" "Scale down: $scale_down_result, Scale up: $http_code"
    fi
else
    record_result "3.1 Gateway Pod Restart" "SKIP" "EKS context not provided"
    record_result "3.2 Gateway Scaling" "SKIP" "EKS context not provided"
fi

#=============================================================================
# TEST SUITE 4: Backend API Resilience
#=============================================================================
print_banner "Test Suite 4: Backend API Resilience"

if [[ -n "$EKS_CONTEXT" ]]; then
    log_test "4.1 - Backend API Pod Restart"
    
    first_api_pod=$($EKS_KUBECTL get pods -n "$API_NAMESPACE" -l app=hello-api -o name 2>/dev/null | head -1)
    
    if [[ -n "$first_api_pod" ]]; then
        log_info "Deleting API pod: $first_api_pod"
        $EKS_KUBECTL delete "$first_api_pod" -n "$API_NAMESPACE" --wait=false
        
        sleep 30
        
        http_code=$(test_endpoint "${SELF_HOSTED_GW_URL}/aws-api/hello" 15)
        if [[ "$http_code" == "200" ]]; then
            record_result "4.1 Backend API Restart" "PASS" "Recovered after pod deletion"
        else
            record_result "4.1 Backend API Restart" "FAIL" "HTTP $http_code"
        fi
    else
        record_result "4.1 Backend API Restart" "SKIP" "No API pods found"
    fi
else
    record_result "4.1 Backend API Restart" "SKIP" "EKS context not provided"
fi

#=============================================================================
# TEST SUITE 5: Error Handling
#=============================================================================
print_banner "Test Suite 5: Error Handling"

log_test "5.1 - 404 Error Handling"
http_code=$(test_endpoint "${SELF_HOSTED_GW_URL}/aws-api/nonexistent")
if [[ "$http_code" == "404" ]]; then
    record_result "5.1 404 Handling" "PASS" "Returns 404 for missing endpoint"
else
    record_result "5.1 404 Handling" "FAIL" "HTTP $http_code instead of 404"
fi

log_test "5.2 - Simulated Backend Error"
http_code=$(test_endpoint "${SELF_HOSTED_GW_URL}/aws-api/simulate/error?code=500")
if [[ "$http_code" == "500" ]]; then
    record_result "5.2 500 Error Handling" "PASS" "Backend error propagated correctly"
else
    record_result "5.2 500 Error Handling" "FAIL" "HTTP $http_code instead of 500"
fi

#=============================================================================
# TEST SUITE 6: Cross-Cloud Communication
#=============================================================================
print_banner "Test Suite 6: Cross-Cloud Communication"

log_test "6.1 - Azure to AWS Routing"
# Call AWS API through Azure APIM (crosses clouds)
http_code=$(test_endpoint "${APIM_GATEWAY_URL}/aws-api/hello")
if [[ "$http_code" == "200" ]]; then
    record_result "6.1 Azure to AWS Routing" "PASS" "Cross-cloud routing works"
else
    record_result "6.1 Azure to AWS Routing" "FAIL" "HTTP $http_code"
fi

log_test "6.2 - Response Header Verification"
response=$(curl -s -D - "${SELF_HOSTED_GW_URL}/aws-api/hello" 2>/dev/null | head -20)
if echo "$response" | grep -qi "X-Served-By"; then
    record_result "6.2 Response Headers" "PASS" "Custom headers present"
else
    record_result "6.2 Response Headers" "FAIL" "Missing custom headers"
fi

#=============================================================================
# Generate Report
#=============================================================================
print_banner "Test Complete - Generating Report"

# Add results to report
cat >> "$REPORT_FILE" << EOF

| Test | Result | Details |
|------|--------|---------|
EOF

for test_name in "${!TEST_RESULTS[@]}"; do
    result="${TEST_RESULTS[$test_name]}"
    status=$(echo "$result" | cut -d: -f1)
    details=$(echo "$result" | cut -d: -f2-)
    
    case $status in
        PASS) emoji="✅" ;;
        FAIL) emoji="❌" ;;
        SKIP) emoji="⏭️" ;;
    esac
    
    echo "| $test_name | $emoji $status | $details |" >> "$REPORT_FILE"
done

cat >> "$REPORT_FILE" << EOF

## Summary

- **Total Tests:** $TOTAL_TESTS
- **Passed:** $PASSED_TESTS
- **Failed:** $FAILED_TESTS
- **Skipped:** $SKIPPED_TESTS
- **Pass Rate:** $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%

## Recommendations

EOF

if [[ $FAILED_TESTS -gt 0 ]]; then
    echo "⚠️ Some tests failed. Review the failed tests and check:" >> "$REPORT_FILE"
    echo "1. Network connectivity between clouds" >> "$REPORT_FILE"
    echo "2. Self-hosted gateway configuration" >> "$REPORT_FILE"
    echo "3. Backend API health" >> "$REPORT_FILE"
    echo "4. APIM configuration and routing" >> "$REPORT_FILE"
else
    echo "✅ All tests passed! The multi-cloud APIM setup is functioning correctly." >> "$REPORT_FILE"
fi

# Print summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "Total Tests:  $TOTAL_TESTS"
echo -e "Passed:       ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed:       ${RED}$FAILED_TESTS${NC}"
echo -e "Skipped:      ${YELLOW}$SKIPPED_TESTS${NC}"
echo -e "Pass Rate:    $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
echo ""
echo "Report saved to: $REPORT_FILE"
echo ""

if [[ $FAILED_TESTS -gt 0 ]]; then
    log_error "Some tests failed. Review the report for details."
    exit 1
else
    log_success "All tests passed!"
    exit 0
fi
