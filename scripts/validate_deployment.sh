#!/usr/bin/env bash
# Comprehensive deployment validation script

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_status "=== Homelab Deployment Validation ==="

# Test connectivity
print_status "Testing VM connectivity..."
for host in 10.14.185.35 10.14.185.67 10.14.185.213; do
    if ping -c 1 -W 2 $host >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} VM $host is reachable"
    else
        echo -e "${RED}✗${NC} VM $host is unreachable"
    fi
done

# Test services on vm-a
print_status "\nTesting observability services on vm-a (10.14.185.35)..."

# Prometheus
if curl -s http://10.14.185.35:9090/-/ready 2>/dev/null | grep -q "Ready"; then
    echo -e "${GREEN}✓${NC} Prometheus is ready"
else
    echo -e "${RED}✗${NC} Prometheus is not ready"
fi

# Grafana  
if curl -s http://10.14.185.35:3000/api/health 2>/dev/null | jq -r '.database' | grep -q "ok"; then
    echo -e "${GREEN}✓${NC} Grafana is healthy"
else
    echo -e "${YELLOW}⚠${NC} Grafana may not be fully ready"
fi

# Loki
if curl -s http://10.14.185.35:3100/ready 2>/dev/null | grep -q "ready"; then
    echo -e "${GREEN}✓${NC} Loki is ready"
else
    echo -e "${RED}✗${NC} Loki is not ready"
fi

# Node Exporter
if curl -s http://10.14.185.35:9100/metrics 2>/dev/null | head -1 | grep -q "HELP"; then
    echo -e "${GREEN}✓${NC} Node Exporter is serving metrics"
else
    echo -e "${RED}✗${NC} Node Exporter is not responding"
fi

# Test Prometheus targets
print_status "\nChecking Prometheus targets..."
targets=$(curl -s http://10.14.185.35:9090/api/v1/targets 2>/dev/null | jq -r '.data.activeTargets[].health' 2>/dev/null | sort | uniq -c)
echo "$targets"

# Summary
print_status "\n=== Deployment Summary ==="
echo "Infrastructure: 3 VMs deployed via Multipass"
echo "Container Runtime: Podman with Quadlet systemd integration"
echo "Observability: Prometheus, Grafana, Loki, Promtail, Node Exporter"
echo ""
echo "Access URLs:"
echo "  Prometheus: http://10.14.185.35:9090"
echo "  Grafana: http://10.14.185.35:3000 (admin/admin)"
echo "  Loki: http://10.14.185.35:3100"
echo ""
echo "Repository: https://github.com/yourusername/podman-homelab"