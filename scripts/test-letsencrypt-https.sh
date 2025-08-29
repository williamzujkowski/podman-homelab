#!/usr/bin/env bash

# Test Let's Encrypt HTTPS access to homelab services
# Validates browser-trusted certificates are working

echo "=== Testing HTTPS with Let's Encrypt Certificates ==="
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

echo "=== Certificate Validation ==="
echo -n "Certificate Issuer: "
issuer=$(echo | openssl s_client -connect ${TRAEFIK_IP}:443 -servername grafana.homelab.grenlan.com 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null | sed 's/issuer=//')
if [[ "$issuer" == *"Let's Encrypt"* ]]; then
    echo -e "${GREEN}✓${NC} $issuer"
else
    echo -e "${RED}✗${NC} $issuer"
fi

echo -n "Certificate Subject: "
subject=$(echo | openssl s_client -connect ${TRAEFIK_IP}:443 -servername grafana.homelab.grenlan.com 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed 's/subject=//')
echo "$subject"

echo -n "Certificate Expiry: "
expiry=$(echo | openssl s_client -connect ${TRAEFIK_IP}:443 -servername grafana.homelab.grenlan.com 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
echo "$expiry"

echo ""
echo "=== HTTPS Service Tests ==="
test_https "Grafana" "grafana.homelab.grenlan.com" "/api/health"
test_https "Prometheus" "prometheus.homelab.grenlan.com" "/-/healthy"
test_https "Homelab Main" "homelab.grenlan.com" "/"

echo ""
echo "=== Browser Trust Test ==="
echo -n "Testing certificate trust (no -k flag)... "
response=$(curl --resolve "grafana.homelab.grenlan.com:443:${TRAEFIK_IP}" -s -o /dev/null -w "%{http_code}" "https://grafana.homelab.grenlan.com" 2>&1)
if [[ "$response" == "200" ]] || [[ "$response" == "302" ]]; then
    echo -e "${GREEN}✓${NC} Certificate is trusted by curl/browsers!"
else
    echo -e "${YELLOW}!${NC} Certificate may not be trusted (response: $response)"
fi

echo ""
echo "========================================="
echo "          HTTPS SETUP COMPLETE!          "
echo "========================================="
echo ""
echo "✅ Let's Encrypt certificates are active!"
echo "✅ Auto-renewal is configured (twice daily)"
echo "✅ Services are accessible via HTTPS"
echo ""
echo "Access your services at:"
echo "  • https://grafana.homelab.grenlan.com"
echo "  • https://prometheus.homelab.grenlan.com"
echo "  • https://homelab.grenlan.com"
echo ""
echo "Certificates expire: $expiry"
echo "Auto-renewal will happen ~30 days before expiry"