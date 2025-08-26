#!/usr/bin/env bash
set -euo pipefail

# Service verification script
# Checks health of deployed services

echo "=== Service Health Check ==="

# Default targets (can be overridden with arguments)
HOSTS=${1:-"vm-a vm-b vm-c"}

# Service endpoints to check
declare -A SERVICES=(
    ["prometheus"]="9090/api/v1/query?query=up"
    ["grafana"]="3000/api/health"
    ["loki"]="3100/ready"
    ["node_exporter"]="9100/metrics"
)

failed=0
total=0

for host in $HOSTS; do
    echo ""
    echo "Checking $host:"
    
    for service in "${!SERVICES[@]}"; do
        endpoint="${SERVICES[$service]}"
        port="${endpoint%%/*}"
        path="${endpoint#*/}"
        
        url="http://${host}:${port}/${path}"
        
        echo -n "  $service ($port): "
        total=$((total + 1))
        
        if curl -sf --max-time 5 "$url" >/dev/null 2>&1; then
            echo "✓ OK"
        else
            echo "✗ FAILED"
            failed=$((failed + 1))
        fi
    done
done

echo ""
echo "=== Summary ==="
echo "Total checks: $total"
echo "Passed: $((total - failed))"
echo "Failed: $failed"

if [ $failed -eq 0 ]; then
    echo "✓ All services healthy"
    exit 0
else
    echo "✗ Some services are unhealthy"
    exit 1
fi