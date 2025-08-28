#!/bin/bash

# Cloudflare Configuration Validation Script
# Tests DNS, SSL, security headers, and service availability

set -e

echo "=== Cloudflare Configuration Validation ==="
echo "Testing your homelab setup at grenlan.com"
echo

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test function
test_check() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

FAILED_TESTS=0

# 1. DNS Resolution Tests
echo "1. DNS Resolution Tests"
echo "-----------------------"

# Test main homelab domain
dig +short homelab.grenlan.com > /dev/null 2>&1
test_check $? "homelab.grenlan.com resolves"

# Test wildcard subdomain
dig +short grafana.homelab.grenlan.com > /dev/null 2>&1
test_check $? "*.homelab.grenlan.com (wildcard) resolves"

# Check if proxied through Cloudflare
IP=$(dig +short homelab.grenlan.com | head -1)
if [[ $IP =~ ^104\.|^172\.6[4-9]\.|^172\.7[0-1]\.|^173\.245\.|^103\.21\.|^103\.22\.|^103\.31\.|^131\.0\.|^141\.101\.|^108\.162\.|^190\.93\.|^188\.114\.|^197\.234\.|^198\.41\. ]]; then
    echo -e "${GREEN}✓${NC} Domain is proxied through Cloudflare (IP: $IP)"
else
    echo -e "${YELLOW}⚠${NC} Domain may not be proxied through Cloudflare (IP: $IP)"
fi

echo

# 2. SSL Certificate Tests
echo "2. SSL Certificate Tests"
echo "------------------------"

# Test SSL connection
timeout 5 openssl s_client -connect homelab.grenlan.com:443 -servername homelab.grenlan.com < /dev/null 2>/dev/null | grep -q "Verify return code: 0"
test_check $? "SSL certificate is valid"

# Check certificate issuer
ISSUER=$(echo | openssl s_client -connect homelab.grenlan.com:443 -servername homelab.grenlan.com 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null | grep -oP 'O=\K[^,]+' || echo "Unknown")
if [[ $ISSUER == *"Cloudflare"* ]]; then
    echo -e "${GREEN}✓${NC} Using Cloudflare Origin Certificate"
elif [[ $ISSUER == *"Let's Encrypt"* ]]; then
    echo -e "${GREEN}✓${NC} Using Let's Encrypt Certificate"
else
    echo -e "${YELLOW}⚠${NC} Certificate issuer: $ISSUER"
fi

# Check certificate expiry
EXPIRY=$(echo | openssl s_client -connect homelab.grenlan.com:443 -servername homelab.grenlan.com 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
if [ -n "$EXPIRY" ]; then
    echo -e "${GREEN}✓${NC} Certificate expires: $EXPIRY"
else
    echo -e "${RED}✗${NC} Could not determine certificate expiry"
fi

echo

# 3. Security Headers Tests
echo "3. Security Headers Tests"
echo "-------------------------"

# Get headers
HEADERS=$(curl -sI https://homelab.grenlan.com 2>/dev/null)

# Check for security headers
echo "$HEADERS" | grep -qi "strict-transport-security"
test_check $? "HSTS header present"

echo "$HEADERS" | grep -qi "cf-ray"
test_check $? "Cloudflare headers present (CF-RAY)"

echo "$HEADERS" | grep -qi "x-frame-options\|content-security-policy.*frame-ancestors"
test_check $? "Clickjacking protection present"

echo

# 4. Service Availability Tests
echo "4. Service Availability Tests"
echo "-----------------------------"

# Test each service endpoint
SERVICES=(
    "grafana.homelab.grenlan.com:Grafana"
    "prometheus.homelab.grenlan.com:Prometheus"
    "traefik.homelab.grenlan.com:Traefik"
    "minio.homelab.grenlan.com:MinIO"
)

for SERVICE in "${SERVICES[@]}"; do
    URL="${SERVICE%%:*}"
    NAME="${SERVICE##*:}"
    
    HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" -L "https://$URL" 2>/dev/null)
    
    if [[ $HTTP_CODE == "200" ]] || [[ $HTTP_CODE == "401" ]] || [[ $HTTP_CODE == "302" ]]; then
        echo -e "${GREEN}✓${NC} $NAME is accessible (HTTP $HTTP_CODE)"
    else
        echo -e "${RED}✗${NC} $NAME returned HTTP $HTTP_CODE"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done

echo

# 5. Cloudflare Features Tests
echo "5. Cloudflare Features Tests"
echo "----------------------------"

# Check if Always Use HTTPS is working
HTTP_RESP=$(curl -sI -o /dev/null -w "%{http_code}" http://homelab.grenlan.com 2>/dev/null)
HTTPS_RESP=$(curl -sI -o /dev/null -w "%{http_code}" -L http://homelab.grenlan.com 2>/dev/null)

if [[ $HTTP_RESP == "301" ]] || [[ $HTTP_RESP == "302" ]]; then
    echo -e "${GREEN}✓${NC} HTTP to HTTPS redirect working"
else
    echo -e "${YELLOW}⚠${NC} HTTP to HTTPS redirect may not be configured (HTTP $HTTP_RESP)"
fi

# Check server header obfuscation
SERVER_HEADER=$(curl -sI https://homelab.grenlan.com 2>/dev/null | grep -i "^server:" | cut -d: -f2- | xargs)
if [[ -z "$SERVER_HEADER" ]] || [[ "$SERVER_HEADER" == "cloudflare" ]]; then
    echo -e "${GREEN}✓${NC} Server header properly hidden/masked"
else
    echo -e "${YELLOW}⚠${NC} Server header exposed: $SERVER_HEADER"
fi

echo

# 6. Performance Tests
echo "6. Performance Tests"
echo "--------------------"

# Test response time
RESPONSE_TIME=$(curl -o /dev/null -s -w "%{time_total}" https://homelab.grenlan.com 2>/dev/null)
RESPONSE_MS=$(echo "$RESPONSE_TIME * 1000" | bc | cut -d. -f1)

if [ "$RESPONSE_MS" -lt 1000 ]; then
    echo -e "${GREEN}✓${NC} Response time: ${RESPONSE_MS}ms (Good)"
elif [ "$RESPONSE_MS" -lt 3000 ]; then
    echo -e "${YELLOW}⚠${NC} Response time: ${RESPONSE_MS}ms (Acceptable)"
else
    echo -e "${RED}✗${NC} Response time: ${RESPONSE_MS}ms (Slow)"
fi

# Check if gzip/brotli compression is enabled
ENCODING=$(curl -sI -H "Accept-Encoding: gzip, br" https://homelab.grenlan.com 2>/dev/null | grep -i "content-encoding" | cut -d: -f2 | xargs)
if [[ -n "$ENCODING" ]]; then
    echo -e "${GREEN}✓${NC} Compression enabled: $ENCODING"
else
    echo -e "${YELLOW}⚠${NC} Compression may not be enabled"
fi

echo

# 7. Local Connectivity Test
echo "7. Local Connectivity Tests"
echo "---------------------------"

# Test if services are accessible locally (bypass Cloudflare)
echo "Testing direct access to Pi cluster..."

# Try to reach Traefik directly
timeout 2 curl -k -s -o /dev/null https://192.168.1.11 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Direct access to Traefik (pi-b) working"
else
    echo -e "${YELLOW}⚠${NC} Cannot reach Traefik directly (this is OK if firewall blocks it)"
fi

echo

# Summary
echo "======================================="
if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}All tests passed! Your Cloudflare configuration is working correctly.${NC}"
else
    echo -e "${YELLOW}$FAILED_TESTS test(s) failed. Please review the configuration.${NC}"
fi
echo "======================================="

echo
echo "Additional Manual Checks:"
echo "1. Visit https://www.ssllabs.com/ssltest/analyze.html?d=homelab.grenlan.com"
echo "2. Check https://securityheaders.com/?q=homelab.grenlan.com"
echo "3. Monitor Cloudflare Analytics dashboard for traffic and threats"
echo "4. Review Cloudflare Firewall Events for blocked requests"

exit $FAILED_TESTS