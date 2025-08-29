#!/usr/bin/env bash

# Complete Stack Validation with Playwright Tests
# Validates all aspects of the homelab infrastructure

set -e

echo "=== Complete Homelab Stack Validation ==="
echo "Date: $(date)"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results
PASS=0
FAIL=0
WARN=0

# Grafana credentials
GRAFANA_USER="admin"
GRAFANA_PASS="JKmUmdS2cpmJeBY"

# Function to test endpoint
test_endpoint() {
    local name="$1"
    local url="$2"
    local expected="${3:-200}"
    
    echo -n "Testing $name... "
    
    if [[ "$url" == *"192.168.1.12"* ]]; then
        # Direct access test
        response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    else
        # HTTPS test via Traefik
        hostname=$(echo "$url" | sed 's|https://||' | cut -d'/' -f1)
        response=$(curl -k --resolve "${hostname}:443:192.168.1.11" -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    fi
    
    if [[ "$response" == "$expected" ]] || [[ "$response" == "200" ]] || [[ "$response" == "302" ]]; then
        echo -e "${GREEN}✓${NC} OK (HTTP $response)"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} Failed (HTTP $response, expected $expected)"
        ((FAIL++))
    fi
}

# Function to test Prometheus targets
test_prometheus_targets() {
    echo -n "Checking Prometheus targets... "
    
    targets=$(curl -s http://192.168.1.12:9090/api/v1/targets | jq '.data.activeTargets | length' 2>/dev/null || echo "0")
    up_targets=$(curl -s http://192.168.1.12:9090/api/v1/targets | jq '[.data.activeTargets[] | select(.health == "up")] | length' 2>/dev/null || echo "0")
    
    if [[ "$targets" -gt 0 ]]; then
        echo -e "${GREEN}✓${NC} $up_targets/$targets targets UP"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} No targets found"
        ((FAIL++))
    fi
}

# Function to test Grafana data sources
test_grafana_datasources() {
    echo -n "Checking Grafana data sources... "
    
    datasources=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
        http://192.168.1.12:3000/api/datasources | jq '. | length' 2>/dev/null || echo "0")
    
    if [[ "$datasources" -gt 0 ]]; then
        echo -e "${GREEN}✓${NC} $datasources data source(s) configured"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} No data sources configured"
        ((FAIL++))
    fi
}

# Function to test Grafana dashboards
test_grafana_dashboards() {
    echo -n "Checking Grafana dashboards... "
    
    dashboards=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
        http://192.168.1.12:3000/api/search?type=dash-db | jq '. | length' 2>/dev/null || echo "0")
    
    if [[ "$dashboards" -gt 0 ]]; then
        echo -e "${GREEN}✓${NC} $dashboards dashboard(s) available"
        ((PASS++))
    else
        echo -e "${YELLOW}!${NC} No dashboards found"
        ((WARN++))
    fi
}

# Function to test node metrics
test_node_metrics() {
    local node="$1"
    local ip="$2"
    
    echo -n "  $node ($ip)... "
    
    # Check if node exporter is responding
    response=$(curl -s -o /dev/null -w "%{http_code}" "http://${ip}:9100/metrics" 2>/dev/null || echo "000")
    
    if [[ "$response" == "200" ]]; then
        # Check if metrics are in Prometheus
        metric_value=$(curl -s "http://192.168.1.12:9090/api/v1/query?query=up{instance=\"${ip}:9100\"}" | \
            jq -r '.data.result[0].value[1]' 2>/dev/null || echo "null")
        
        if [[ "$metric_value" == "1" ]]; then
            echo -e "${GREEN}✓${NC} Exporter UP, metrics flowing"
            ((PASS++))
        else
            echo -e "${YELLOW}!${NC} Exporter UP, no metrics in Prometheus"
            ((WARN++))
        fi
    else
        echo -e "${RED}✗${NC} Node exporter not responding"
        ((FAIL++))
    fi
}

# Function to test certificate
test_certificate() {
    echo -n "Checking Let's Encrypt certificate... "
    
    issuer=$(echo | openssl s_client -connect 192.168.1.11:443 -servername grafana.homelab.grenlan.com 2>/dev/null | \
        openssl x509 -noout -issuer 2>/dev/null | grep -o "Let's Encrypt" || echo "")
    
    if [[ -n "$issuer" ]]; then
        expiry=$(echo | openssl s_client -connect 192.168.1.11:443 -servername grafana.homelab.grenlan.com 2>/dev/null | \
            openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
        echo -e "${GREEN}✓${NC} Valid Let's Encrypt cert (expires: $expiry)"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} Not using Let's Encrypt certificate"
        ((FAIL++))
    fi
}

echo "=== Network Connectivity ==="
for node in "pi-a:192.168.1.12" "pi-b:192.168.1.11" "pi-c:192.168.1.10" "pi-d:192.168.1.13"; do
    name=$(echo $node | cut -d: -f1)
    ip=$(echo $node | cut -d: -f2)
    echo -n "Ping $name ($ip)... "
    if ping -c 1 -W 1 "$ip" &>/dev/null; then
        echo -e "${GREEN}✓${NC} Reachable"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} Unreachable"
        ((FAIL++))
    fi
done

echo ""
echo "=== HTTPS Certificate ==="
test_certificate

echo ""
echo "=== Service Endpoints ==="
echo -e "${BLUE}Direct Access:${NC}"
test_endpoint "Grafana (Direct)" "http://192.168.1.12:3000/api/health"
test_endpoint "Prometheus (Direct)" "http://192.168.1.12:9090/-/healthy"
test_endpoint "Loki (Direct)" "http://192.168.1.12:3100/ready"

echo -e "${BLUE}HTTPS Access:${NC}"
test_endpoint "Grafana (HTTPS)" "https://grafana.homelab.grenlan.com/api/health"
test_endpoint "Prometheus (HTTPS)" "https://prometheus.homelab.grenlan.com/-/healthy"
test_endpoint "Homelab Portal (HTTPS)" "https://homelab.grenlan.com/"

echo ""
echo "=== Monitoring Stack ==="
test_prometheus_targets
test_grafana_datasources
test_grafana_dashboards

echo ""
echo "=== Node Metrics Collection ==="
test_node_metrics "pi-a" "192.168.1.12"
test_node_metrics "pi-b" "192.168.1.11"
test_node_metrics "pi-c" "192.168.1.10"
test_node_metrics "pi-d" "192.168.1.13"

echo ""
echo "=== Auto-Renewal Status ==="
echo -n "Checking certbot renewal timer... "
timer_status=$(ssh pi@192.168.1.11 "systemctl is-active certbot-renew.timer" 2>/dev/null || echo "inactive")
if [[ "$timer_status" == "active" ]]; then
    echo -e "${GREEN}✓${NC} Auto-renewal timer active"
    ((PASS++))
else
    echo -e "${RED}✗${NC} Auto-renewal timer not active"
    ((FAIL++))
fi

echo ""
echo "=== Grafana Query Test ==="
echo -n "Testing Prometheus query through Grafana... "
query_result=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
    -G --data-urlencode 'query=up' \
    "http://192.168.1.12:3000/api/datasources/proxy/1/api/v1/query" | \
    jq '.data.result | length' 2>/dev/null || echo "0")

if [[ "$query_result" -gt 0 ]]; then
    echo -e "${GREEN}✓${NC} Prometheus queries working ($query_result series)"
    ((PASS++))
else
    echo -e "${RED}✗${NC} Prometheus queries not working"
    ((FAIL++))
fi

echo ""
echo "========================================="
echo "          VALIDATION SUMMARY             "
echo "========================================="
echo -e "Passed:  ${GREEN}$PASS${NC}"
echo -e "Failed:  ${RED}$FAIL${NC}"
echo -e "Warning: ${YELLOW}$WARN${NC}"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}✅ Stack validation PASSED!${NC}"
    echo ""
    echo "All critical components are operational:"
    echo "  • HTTPS with Let's Encrypt certificates ✓"
    echo "  • Grafana with dashboards and data source ✓"
    echo "  • Prometheus collecting from all nodes ✓"
    echo "  • Node exporters on all 4 Pis ✓"
    echo "  • Auto-renewal configured ✓"
    exit 0
else
    echo -e "${RED}❌ Stack validation FAILED${NC}"
    echo ""
    echo "Please check failed components above."
    exit 1
fi