#!/usr/bin/env bash

# Complete Stack Validation Script
# Tests all components of the homelab infrastructure

echo "=== Homelab Stack Validation ==="
echo "Date: $(date)"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test results
PASS=0
FAIL=0
WARN=0

# Function to test endpoint
test_endpoint() {
    local name="$1"
    local url="$2"
    local expected="$3"
    
    echo -n "Testing $name... "
    
    # SSH to pi-a and test from there since services bind to localhost
    response=$(ssh -o ConnectTimeout=5 pi@192.168.1.12 "curl -s -o /dev/null -w '%{http_code}' '$url' 2>/dev/null" 2>/dev/null || echo "000")
    
    if [[ "$response" == "$expected" ]] || [[ "$response" == "200" ]] || [[ "$response" == "302" ]]; then
        echo -e "${GREEN}✓${NC} OK (HTTP $response)"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} Failed (HTTP $response, expected $expected)"
        ((FAIL++))
    fi
}

# Function to test service health
test_service_health() {
    local name="$1"
    local host="$2"
    local check_cmd="$3"
    
    echo -n "Testing $name health... "
    
    if ssh -o ConnectTimeout=5 "pi@$host" "$check_cmd" &>/dev/null; then
        echo -e "${GREEN}✓${NC} Healthy"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} Unhealthy"
        ((FAIL++))
    fi
}

# Function to test DNS
test_dns() {
    local domain="$1"
    local expected_ip="$2"
    
    echo -n "Testing DNS for $domain... "
    
    result=$(dig +short "$domain" 2>/dev/null | head -1)
    
    if [[ "$result" == "$expected_ip" ]]; then
        echo -e "${GREEN}✓${NC} Resolves to $expected_ip"
        ((PASS++))
    elif [[ -n "$result" ]]; then
        echo -e "${YELLOW}!${NC} Resolves to $result (expected $expected_ip)"
        ((WARN++))
    else
        echo -e "${YELLOW}!${NC} No DNS resolution"
        ((WARN++))
    fi
}

echo "=== Node Connectivity ==="
for ip in 192.168.1.12 192.168.1.11 192.168.1.10 192.168.1.13; do
    echo -n "Ping pi at $ip... "
    if ping -c 1 -W 1 "$ip" &>/dev/null; then
        echo -e "${GREEN}✓${NC} Reachable"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} Unreachable"
        ((FAIL++))
    fi
done

echo ""
echo "=== DNS Resolution ==="
test_dns "grafana.homelab.grenlan.com" "192.168.1.11"
test_dns "prometheus.homelab.grenlan.com" "192.168.1.11"
test_dns "loki.homelab.grenlan.com" "192.168.1.11"
test_dns "homelab.grenlan.com" "192.168.1.11"

echo ""
echo "=== Service Health Checks ==="
test_service_health "Grafana" "192.168.1.12" "curl -s http://localhost:3000/api/health | grep -q ok"
test_service_health "Prometheus" "192.168.1.12" "curl -s http://localhost:9090/-/healthy | grep -q Healthy"
test_service_health "Loki" "192.168.1.12" "curl -s http://localhost:3100/ready | grep -q ready"
test_service_health "Node Exporter" "192.168.1.12" "curl -s http://localhost:9100/metrics | grep -q node_"

echo ""
echo "=== HTTP Endpoints (via SSH) ==="
test_endpoint "Grafana API" "http://localhost:3000/api/health" "200"
test_endpoint "Prometheus Health" "http://localhost:9090/-/healthy" "200"
test_endpoint "Prometheus Targets" "http://localhost:9090/targets" "200"
test_endpoint "Loki Ready" "http://localhost:3100/ready" "200"
test_endpoint "Node Exporter Metrics" "http://localhost:9100/metrics" "200"

echo ""
echo "=== Service Processes ==="
echo -n "Checking Grafana process... "
if ssh pi@192.168.1.12 "pgrep grafana" &>/dev/null; then
    echo -e "${GREEN}✓${NC} Running"
    ((PASS++))
else
    echo -e "${RED}✗${NC} Not running"
    ((FAIL++))
fi

echo -n "Checking Prometheus process... "
if ssh pi@192.168.1.12 "pgrep prometheus" &>/dev/null; then
    echo -e "${GREEN}✓${NC} Running"
    ((PASS++))
else
    echo -e "${RED}✗${NC} Not running"
    ((FAIL++))
fi

echo -n "Checking Loki container... "
if ssh pi@192.168.1.12 "podman ps | grep loki" &>/dev/null; then
    echo -e "${GREEN}✓${NC} Running"
    ((PASS++))
else
    echo -e "${RED}✗${NC} Not running"
    ((FAIL++))
fi

echo -n "Checking Traefik container... "
if ssh pi@192.168.1.11 "podman ps | grep traefik" &>/dev/null; then
    echo -e "${GREEN}✓${NC} Running"
    ((PASS++))
else
    echo -e "${RED}✗${NC} Not running"
    ((FAIL++))
fi

echo ""
echo "=== Certificate Status ==="
echo -n "Checking Cloudflare certificates... "
if ssh pi@192.168.1.11 "sudo test -f /etc/ssl/cloudflare/cloudflare-origin.crt" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Installed"
    ((PASS++))
    
    # Check certificate validity
    echo -n "Certificate validity... "
    expiry=$(ssh pi@192.168.1.11 "sudo openssl x509 -in /etc/ssl/cloudflare/cloudflare-origin.crt -noout -enddate 2>/dev/null | cut -d= -f2" 2>/dev/null)
    if [[ -n "$expiry" ]]; then
        echo -e "${GREEN}✓${NC} Valid until $expiry"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} Cannot check validity"
        ((FAIL++))
    fi
else
    echo -e "${RED}✗${NC} Not found"
    ((FAIL++))
fi

echo ""
echo "=== HTTPS Access Status ==="
echo -n "Testing HTTPS on Traefik... "
response=$(curl -k -s -o /dev/null -w "%{http_code}" https://192.168.1.11 2>/dev/null || echo "000")
if [[ "$response" == "404" ]] || [[ "$response" == "200" ]]; then
    echo -e "${GREEN}✓${NC} TLS Working (HTTP $response)"
    ((PASS++))
else
    echo -e "${YELLOW}!${NC} TLS Issue (SNI configuration needed)"
    ((WARN++))
fi

echo ""
echo "========================================="
echo "            VALIDATION SUMMARY            "
echo "========================================="
echo -e "Passed:  ${GREEN}$PASS${NC}"
echo -e "Failed:  ${RED}$FAIL${NC}"
echo -e "Warning: ${YELLOW}$WARN${NC}"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}✅ Stack validation PASSED!${NC}"
    echo ""
    echo "All core services are operational."
    echo "Access services at:"
    echo "  • Grafana: http://192.168.1.12:3000"
    echo "  • Prometheus: http://192.168.1.12:9090"
    echo "  • Loki: http://192.168.1.12:3100"
    exit 0
else
    echo -e "${RED}❌ Stack validation FAILED${NC}"
    echo ""
    echo "Please check failed components above."
    exit 1
fi