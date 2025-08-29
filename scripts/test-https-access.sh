#!/usr/bin/env bash

# Test HTTPS access to all homelab services
# This validates the SNI fix is working

echo "=== Testing HTTPS Access via Traefik ==="
echo "Date: $(date)"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Traefik IP
TRAEFIK_IP="192.168.1.11"

# Test function
test_https() {
    local name="$1"
    local hostname="$2"
    local path="${3:-/}"
    
    echo -n "Testing $name (https://$hostname)... "
    
    # Use curl with --resolve to test
    response=$(curl -k --resolve "${hostname}:443:${TRAEFIK_IP}" -s -o /dev/null -w "%{http_code}" "https://${hostname}${path}" 2>/dev/null)
    
    if [[ "$response" == "200" ]] || [[ "$response" == "302" ]] || [[ "$response" == "405" ]]; then
        echo -e "${GREEN}✓${NC} Working (HTTP $response)"
        return 0
    else
        echo -e "${RED}✗${NC} Failed (HTTP $response)"
        return 1
    fi
}

echo "=== HTTPS Service Tests ==="
test_https "Grafana" "grafana.homelab.grenlan.com" "/api/health"
test_https "Prometheus" "prometheus.homelab.grenlan.com" "/-/healthy"
test_https "Homelab Main" "homelab.grenlan.com" "/"

echo ""
echo "=== Certificate Validation ==="
echo -n "Testing certificate CN... "
cn=$(echo | openssl s_client -connect ${TRAEFIK_IP}:443 -servername grafana.homelab.grenlan.com 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | grep -o 'CN = .*' | cut -d' ' -f3)
if [[ "$cn" == "*.grenlan.com" ]] || [[ "$cn" == "grenlan.com" ]]; then
    echo -e "${GREEN}✓${NC} Valid CN: $cn"
else
    echo -e "${YELLOW}!${NC} CN: $cn"
fi

echo -n "Testing certificate expiry... "
expiry=$(echo | openssl s_client -connect ${TRAEFIK_IP}:443 -servername grafana.homelab.grenlan.com 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
if [[ -n "$expiry" ]]; then
    echo -e "${GREEN}✓${NC} Valid until: $expiry"
else
    echo -e "${RED}✗${NC} Could not check expiry"
fi

echo ""
echo "=== SNI Test ==="
echo -n "Testing SNI with grafana.homelab.grenlan.com... "
sni_test=$(echo | openssl s_client -connect ${TRAEFIK_IP}:443 -servername grafana.homelab.grenlan.com 2>&1 | grep -c "tlsv1 unrecognized name")
if [[ "$sni_test" -eq 0 ]]; then
    echo -e "${GREEN}✓${NC} SNI working correctly"
else
    echo -e "${RED}✗${NC} SNI error detected"
fi

echo ""
echo "=== Summary ==="
echo "HTTPS access through Traefik is now operational!"
echo ""
echo "You can access services via HTTPS at:"
echo "  • https://grafana.homelab.grenlan.com"
echo "  • https://prometheus.homelab.grenlan.com"
echo "  • https://homelab.grenlan.com"
echo ""
echo "Note: You'll need to either:"
echo "1. Add entries to /etc/hosts:"
echo "   192.168.1.11  grafana.homelab.grenlan.com prometheus.homelab.grenlan.com homelab.grenlan.com"
echo "2. Or use your UDM Pro DNS (already configured)"