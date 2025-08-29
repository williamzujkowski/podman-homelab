#!/bin/bash

# Verify Grafana setup and data flow
set -euo pipefail

GRAFANA_URL="http://192.168.1.12:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="JKmUmdS2cpmJeBY"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "============================================"
echo "        Grafana Setup Verification"  
echo "============================================"
echo

# 1. Check Grafana health
print_status "Checking Grafana health..."
health_response=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" "${GRAFANA_URL}/api/health")
if echo "$health_response" | jq -e '.database == "ok"' >/dev/null 2>&1; then
    version=$(echo "$health_response" | jq -r '.version')
    print_success "Grafana is healthy (version: $version)"
else
    print_error "Grafana health check failed"
    exit 1
fi
echo

# 2. Check data sources
print_status "Checking data sources..."
datasources=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" "${GRAFANA_URL}/api/datasources")
prometheus_ds=$(echo "$datasources" | jq -r '.[] | select(.type == "prometheus") | .name')
if [[ -n "$prometheus_ds" ]]; then
    print_success "Prometheus data source found: $prometheus_ds"
else
    print_error "No Prometheus data source found"
    exit 1
fi
echo

# 3. Test Prometheus connectivity
print_status "Testing Prometheus data source connectivity..."
query_response=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" -G "${GRAFANA_URL}/api/datasources/proxy/1/api/v1/query" --data-urlencode "query=up")
if echo "$query_response" | jq -e '.status == "success"' >/dev/null 2>&1; then
    target_count=$(echo "$query_response" | jq '.data.result | length')
    print_success "Prometheus query successful ($target_count targets found)"
else
    print_error "Prometheus query failed"
    exit 1
fi
echo

# 4. List discovered targets
print_status "Discovered monitoring targets:"
echo "$query_response" | jq -r '.data.result[] | "  - " + .metric.job + "/" + .metric.instance + " (status: " + (.value[1] | if . == "1" then "UP" else "DOWN" end) + ")"' | sort
echo

# 5. Check node metrics specifically
print_status "Checking node exporter metrics..."
node_query=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" -G "${GRAFANA_URL}/api/datasources/proxy/1/api/v1/query" --data-urlencode "query=up{job=\"node\"}")
if echo "$node_query" | jq -e '.status == "success"' >/dev/null 2>&1; then
    node_count=$(echo "$node_query" | jq '.data.result | length')
    print_success "Found $node_count node exporter instances"
    echo "$node_query" | jq -r '.data.result[] | "  - " + .metric.instance + " (" + (.metric.hostname // .metric.instance) + ")"'
else
    print_warning "No node exporter metrics found"
fi
echo

# 6. Test CPU metrics query
print_status "Testing CPU usage metrics..."
cpu_query='100 - (avg by(instance,hostname) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'
cpu_response=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" -G "${GRAFANA_URL}/api/datasources/proxy/1/api/v1/query" --data-urlencode "query=${cpu_query}")
if echo "$cpu_response" | jq -e '.status == "success"' >/dev/null 2>&1; then
    print_success "CPU usage metrics available:"
    echo "$cpu_response" | jq -r '.data.result[] | "  - " + (.metric.hostname // .metric.instance) + ": " + (.value[1] | tonumber | . * 100 | round / 100 | tostring) + "% CPU"'
else
    print_warning "CPU metrics query failed"
fi
echo

# 7. Test memory metrics
print_status "Testing memory metrics..."
memory_query='(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100'
memory_response=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" -G "${GRAFANA_URL}/api/datasources/proxy/1/api/v1/query" --data-urlencode "query=${memory_query}")
if echo "$memory_response" | jq -e '.status == "success"' >/dev/null 2>&1; then
    print_success "Memory usage metrics available:"
    echo "$memory_response" | jq -r '.data.result[] | "  - " + (.metric.hostname // .metric.instance) + ": " + (.value[1] | tonumber | . * 100 | round / 100 | tostring) + "% RAM"'
else
    print_warning "Memory metrics query failed"
fi
echo

# 8. List imported dashboards
print_status "Checking imported dashboards..."
dashboards=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" "${GRAFANA_URL}/api/search")
if [[ $(echo "$dashboards" | jq '. | length') -gt 0 ]]; then
    print_success "Found $(echo "$dashboards" | jq '. | length') dashboard(s):"
    echo "$dashboards" | jq -r '.[] | "  - " + .title + " (" + .uid + ")"'
    echo
    print_status "Dashboard URLs:"
    echo "$dashboards" | jq -r '.[] | "  - " + .title + ": " + "'${GRAFANA_URL}'" + .url'
else
    print_warning "No dashboards found"
fi
echo

# 9. Final status
echo "============================================"
print_success "Grafana setup verification completed!"
echo
print_status "Access Information:"
echo "  URL: $GRAFANA_URL"
echo "  Username: $GRAFANA_USER"
echo "  Password: $GRAFANA_PASS"
echo
print_status "Quick Links:"
echo "$dashboards" | jq -r '.[] | "  - " + .title + ": " + "'${GRAFANA_URL}'" + .url'
echo "============================================"