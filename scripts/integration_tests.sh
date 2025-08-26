#!/usr/bin/env bash
# End-to-end integration tests

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

test_service() {
    local name=$1
    local url=$2
    local expected=$3
    
    echo -n "Testing $name... "
    if curl -s --max-time 5 "$url" 2>/dev/null | grep -q "$expected"; then
        echo -e "${GREEN}✓${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC}"
        ((TESTS_FAILED++))
    fi
}

echo "=== Homelab Integration Tests ==="
echo ""

# Test Prometheus
test_service "Prometheus API" "http://10.14.185.35:9090/api/v1/query?query=up" "success"

# Test Node Exporters
test_service "Node Exporter vm-a" "http://10.14.185.35:9100/metrics" "node_"
test_service "Node Exporter vm-b" "http://10.14.185.67:9100/metrics" "node_"
test_service "Node Exporter vm-c" "http://10.14.185.213:9100/metrics" "node_"

# Test Loki
test_service "Loki API" "http://10.14.185.35:3100/ready" "ready"

# Test Caddy Ingress
test_service "Caddy Health" "http://10.14.185.67" "Caddy"

# Test Prometheus targets
echo -n "Testing Prometheus targets... "
TARGETS=$(curl -s http://10.14.185.35:9090/api/v1/targets 2>/dev/null | jq -r '.data.activeTargets | length' 2>/dev/null || echo 0)
if [ "$TARGETS" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} ($TARGETS active targets)"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC}"
    ((TESTS_FAILED++))
fi

# Test container health
echo ""
echo "Container Health Status:"
for host in 10.14.185.35 10.14.185.67 10.14.185.213; do
    echo -n "  VM $host: "
    COUNT=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$host "sudo podman ps --format json 2>/dev/null | jq '. | length'" 2>/dev/null || echo 0)
    if [ "$COUNT" -gt 0 ]; then
        echo -e "${GREEN}$COUNT containers running${NC}"
    else
        echo -e "${YELLOW}Unable to check${NC}"
    fi
done

# Summary
echo ""
echo "=== Test Summary ==="
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed${NC}"
    exit 1
fi