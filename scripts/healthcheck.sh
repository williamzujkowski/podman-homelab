#!/bin/bash

set -euo pipefail

# Health check script for monitoring infrastructure
# Returns 0 if all services are healthy, 1 otherwise

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

FAILED=0
SERVICES_CHECKED=0

# Function to check service health
check_service() {
    local name="$1"
    local host="$2"
    local port="$3"
    local endpoint="${4:-/}"
    local expected_response="${5:-}"
    
    SERVICES_CHECKED=$((SERVICES_CHECKED + 1))
    
    echo -n "Checking $name at $host:$port... "
    
    # First check if port is open
    if timeout 5 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
        # Port is open, check HTTP endpoint if specified
        if [[ "$endpoint" != "/" || -n "$expected_response" ]]; then
            response=$(curl -s -m 5 "http://$host:$port$endpoint" 2>/dev/null || echo "FAILED")
            if [[ -n "$expected_response" ]]; then
                if [[ "$response" == *"$expected_response"* ]]; then
                    echo -e "${GREEN}✓ HEALTHY${NC}"
                    return 0
                else
                    echo -e "${RED}✗ UNHEALTHY (bad response)${NC}"
                    FAILED=$((FAILED + 1))
                    return 1
                fi
            else
                if [[ "$response" != "FAILED" ]]; then
                    echo -e "${GREEN}✓ HEALTHY${NC}"
                    return 0
                else
                    echo -e "${RED}✗ UNHEALTHY (no response)${NC}"
                    FAILED=$((FAILED + 1))
                    return 1
                fi
            fi
        else
            echo -e "${GREEN}✓ HEALTHY${NC}"
            return 0
        fi
    else
        echo -e "${RED}✗ UNHEALTHY (port closed)${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

# Check SSH connectivity to VMs
check_ssh() {
    local vm="$1"
    echo -n "Checking SSH to $vm... "
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$vm" "echo OK" &>/dev/null; then
        echo -e "${GREEN}✓ CONNECTED${NC}"
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

echo "========================================="
echo "   Homelab Infrastructure Health Check"
echo "========================================="
echo ""

# Check VM connectivity
echo "VM Connectivity:"
echo "----------------"
check_ssh "vm-a"
check_ssh "vm-b"
check_ssh "vm-c"
echo ""

# Check services through SSH tunnels (if available)
echo "Services (via SSH tunnels):"
echo "---------------------------"
check_service "Grafana" "localhost" "3000" "/api/health" "ok"
check_service "Prometheus" "localhost" "9090" "/-/ready" "Ready"
check_service "Loki" "localhost" "3100" "/ready" "ready"
check_service "Caddy" "localhost" "8080" "/" "Homelab"
echo ""

# Check node exporters directly on VMs
echo "Node Exporters (direct):"
echo "------------------------"
for vm in vm-a vm-b vm-c; do
    ip=$(ssh "$vm" "hostname -I | cut -d' ' -f1" 2>/dev/null || echo "")
    if [[ -n "$ip" ]]; then
        ssh "$vm" "curl -s localhost:9100/metrics | head -1" &>/dev/null
        if [[ $? -eq 0 ]]; then
            echo -e "Node Exporter on $vm: ${GREEN}✓ HEALTHY${NC}"
        else
            echo -e "Node Exporter on $vm: ${RED}✗ UNHEALTHY${NC}"
            FAILED=$((FAILED + 1))
        fi
    else
        echo -e "Node Exporter on $vm: ${YELLOW}⚠ SKIPPED (no connection)${NC}"
    fi
done
echo ""

# Check container status on VMs
echo "Container Services:"
echo "------------------"
for vm in vm-a vm-b vm-c; do
    echo "Containers on $vm:"
    ssh "$vm" "sudo podman ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null | grep -v NAMES" 2>/dev/null || echo "  Unable to check"
done
echo ""

# Summary
echo "========================================="
if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All health checks passed!${NC}"
    echo "Services checked: $SERVICES_CHECKED"
    exit 0
else
    echo -e "${RED}✗ $FAILED health check(s) failed${NC}"
    echo "Services checked: $SERVICES_CHECKED"
    exit 1
fi