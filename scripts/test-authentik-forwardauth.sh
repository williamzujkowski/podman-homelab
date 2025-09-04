#!/bin/bash
set -euo pipefail

# Authentik ForwardAuth Test Script
# =================================
# Tests the ForwardAuth endpoint after manual configuration

AUTHENTIK_HOST="${1:-192.168.1.13:9002}"
BASE_URL="http://${AUTHENTIK_HOST}"
FORWARDAUTH_URL="${BASE_URL}/outpost.goauthentik.io/auth/traefik"

echo "Authentik ForwardAuth Test"
echo "========================="
echo "Testing: ${FORWARDAUTH_URL}"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_result() {
    local status=$1
    local message=$2
    case $status in
        "PASS") echo -e "${GREEN}✅ ${message}${NC}" ;;
        "FAIL") echo -e "${RED}❌ ${message}${NC}" ;;
        "WARN") echo -e "${YELLOW}⚠️  ${message}${NC}" ;;
        *) echo "$message" ;;
    esac
}

# Test 1: Check if Authentik is responding
echo "1. Testing Authentik API accessibility..."
api_response=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/v3/root/config/" || echo "000")

if [[ "$api_response" == "200" ]]; then
    print_result "PASS" "Authentik API is accessible (HTTP 200)"
else
    print_result "FAIL" "Authentik API not accessible (HTTP $api_response)"
    exit 1
fi

echo ""

# Test 2: Check ForwardAuth endpoint
echo "2. Testing ForwardAuth endpoint..."
forwardauth_response=$(curl -s -o /dev/null -w "%{http_code}" "$FORWARDAUTH_URL" || echo "000")

case "$forwardauth_response" in
    200)
        print_result "PASS" "ForwardAuth endpoint is working (HTTP 200 - authenticated)"
        endpoint_working=true
        ;;
    302)
        print_result "PASS" "ForwardAuth endpoint is working (HTTP 302 - redirect to login)"
        endpoint_working=true
        ;;
    401)
        print_result "PASS" "ForwardAuth endpoint is working (HTTP 401 - unauthorized)"
        endpoint_working=true
        ;;
    404)
        print_result "FAIL" "ForwardAuth endpoint not found (HTTP 404)"
        endpoint_working=false
        ;;
    000)
        print_result "FAIL" "ForwardAuth endpoint not reachable (connection error)"
        endpoint_working=false
        ;;
    *)
        print_result "WARN" "ForwardAuth endpoint returned HTTP $forwardauth_response"
        endpoint_working=true
        ;;
esac

echo ""

# Test 3: Check response headers
echo "3. Testing ForwardAuth response headers..."
if [[ "$endpoint_working" == true ]]; then
    headers=$(curl -s -I "$FORWARDAUTH_URL" 2>/dev/null || echo "")
    
    if echo "$headers" | grep -qi "location:"; then
        print_result "PASS" "Redirect header present (expected for unauthenticated request)"
    elif echo "$headers" | grep -qi "x-authentik"; then
        print_result "PASS" "Authentik headers present (user might be authenticated)"
    else
        print_result "WARN" "No specific authentication headers found"
    fi
else
    print_result "FAIL" "Cannot test headers - endpoint not working"
fi

echo ""

# Test 4: Check container health
echo "4. Checking Authentik container health..."
if ssh -o ConnectTimeout=5 pi@192.168.1.13 "echo 'SSH OK'" &>/dev/null; then
    container_status=$(ssh pi@192.168.1.13 "sudo podman ps --format '{{.Names}}: {{.Status}}' | grep authentik" 2>/dev/null || echo "")
    
    if echo "$container_status" | grep -q "authentik-server.*Up.*healthy"; then
        print_result "PASS" "Authentik server container is healthy"
    elif echo "$container_status" | grep -q "authentik-server.*Up.*unhealthy"; then
        print_result "WARN" "Authentik server container is unhealthy but running"
    elif echo "$container_status" | grep -q "authentik-server"; then
        print_result "WARN" "Authentik server container is running (health status unknown)"
    else
        print_result "FAIL" "Authentik server container not found"
    fi
    
    if echo "$container_status" | grep -q "authentik-worker.*Up.*healthy"; then
        print_result "PASS" "Authentik worker container is healthy"
    else
        print_result "WARN" "Authentik worker container status unknown"
    fi
else
    print_result "FAIL" "Cannot SSH to 192.168.1.13 to check containers"
fi

echo ""

# Test 5: Test with authentication headers (simulate Traefik)
echo "5. Testing with Traefik-style headers..."
test_response=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "X-Forwarded-Proto: https" \
    -H "X-Forwarded-Host: test.homelab.grenlan.com" \
    -H "X-Forwarded-Uri: /" \
    "$FORWARDAUTH_URL" || echo "000")

case "$test_response" in
    302|401)
        print_result "PASS" "ForwardAuth responds correctly to Traefik-style request"
        ;;
    200)
        print_result "PASS" "ForwardAuth allows access (user may be authenticated)"
        ;;
    *)
        print_result "WARN" "ForwardAuth response: HTTP $test_response"
        ;;
esac

echo ""

# Summary
echo "================================="
echo "SUMMARY"
echo "================================="

if [[ "$endpoint_working" == true ]]; then
    print_result "PASS" "ForwardAuth endpoint is configured and working!"
    echo ""
    echo "✅ Configuration Status: READY"
    echo ""
    echo "You can now use the Traefik middleware to protect services:"
    echo "   middlewares:"
    echo "     - authentik-auth@file"
    echo ""
    echo "To test with a real service:"
    echo "1. Apply the middleware to a Traefik route"
    echo "2. Access the protected service URL"
    echo "3. You should be redirected to: https://auth.homelab.grenlan.com"
    echo "4. Login with: akadmin / ChangeMe123!"
    echo "5. You should be redirected back to the service"
    echo ""
else
    print_result "FAIL" "ForwardAuth endpoint is NOT working"
    echo ""
    echo "❌ Configuration Status: INCOMPLETE"
    echo ""
    echo "Please complete the manual configuration steps:"
    echo "1. Access: ${BASE_URL}/if/flow/initial-setup/"
    echo "2. Create admin user if needed"
    echo "3. Login to admin interface: ${BASE_URL}"
    echo "4. Create Traefik Proxy Provider"
    echo "5. Configure Embedded Outpost"
    echo ""
    echo "See: /home/william/git/podman-homelab/docs/authentik-forwardauth-configuration.md"
    echo ""
    exit 1
fi