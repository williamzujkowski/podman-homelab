#!/bin/bash
set -euo pipefail

# Authentik ForwardAuth Configuration Script
# ==========================================
# This script configures Authentik to provide ForwardAuth for Traefik

AUTHENTIK_HOST="${1:-192.168.1.13:9002}"
ADMIN_PASSWORD="${2:-ChangeMe123!}"
ADMIN_EMAIL="${3:-admin@homelab.grenlan.com}"

BASE_URL="http://${AUTHENTIK_HOST}"
FORWARDAUTH_URL="${BASE_URL}/outpost.goauthentik.io/auth/traefik"

echo "Authentik ForwardAuth Configuration"
echo "=================================="
echo "Target: ${BASE_URL}"
echo "Admin Password: ${ADMIN_PASSWORD}"
echo ""

# Function to check if initial setup is needed
check_initial_setup() {
    echo "Checking if initial setup is required..."
    
    response=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/if/flow/initial-setup/" || echo "000")
    
    if [[ "$response" == "200" ]]; then
        echo "✅ Initial setup page accessible - setup required"
        return 0
    elif [[ "$response" == "302" ]] || [[ "$response" == "404" ]]; then
        echo "ℹ️  Initial setup may already be completed"
        return 1
    else
        echo "❌ Could not access initial setup page (HTTP $response)"
        return 2
    fi
}

# Function to test ForwardAuth endpoint
test_forwardauth() {
    echo "Testing ForwardAuth endpoint..."
    
    response=$(curl -s -o /dev/null -w "%{http_code}" "$FORWARDAUTH_URL" || echo "000")
    
    case "$response" in
        200|302)
            echo "✅ ForwardAuth endpoint is working (HTTP $response)"
            return 0
            ;;
        404)
            echo "❌ ForwardAuth endpoint not found (HTTP 404)"
            echo "   This means the provider/outpost is not configured"
            return 1
            ;;
        *)
            echo "❓ ForwardAuth endpoint status: HTTP $response"
            return 2
            ;;
    esac
}

# Function to check API accessibility
test_api_access() {
    echo "Testing API access..."
    
    response=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/v3/root/config/" || echo "000")
    
    if [[ "$response" == "200" ]]; then
        echo "✅ API is accessible"
        return 0
    else
        echo "❌ API not accessible (HTTP $response)"
        return 1
    fi
}

# Function to check container health
check_container_health() {
    echo "Checking Authentik container health..."
    
    # Check if we can SSH to the host
    if ! ssh -o ConnectTimeout=5 pi@192.168.1.13 "echo 'SSH connection OK'" &>/dev/null; then
        echo "❌ Cannot SSH to 192.168.1.13"
        return 1
    fi
    
    # Check container status
    container_status=$(ssh pi@192.168.1.13 "sudo podman ps --format '{{.Names}}: {{.Status}}' | grep authentik" 2>/dev/null || echo "")
    
    if [[ -n "$container_status" ]]; then
        echo "Container status:"
        echo "$container_status"
    else
        echo "❌ Authentik containers not found"
        return 1
    fi
    
    return 0
}

# Main configuration function
main() {
    echo "Starting Authentik ForwardAuth configuration..."
    echo ""
    
    # Step 1: Check container health
    if ! check_container_health; then
        echo "❌ Container health check failed"
        exit 1
    fi
    echo ""
    
    # Step 2: Check API access
    if ! test_api_access; then
        echo "❌ API access check failed"
        exit 1
    fi
    echo ""
    
    # Step 3: Check if ForwardAuth is already working
    if test_forwardauth; then
        echo ""
        echo "✅ ForwardAuth is already configured and working!"
        echo "   No further action needed."
        exit 0
    fi
    echo ""
    
    # Step 4: Check if initial setup is needed
    setup_needed=false
    if check_initial_setup; then
        setup_needed=true
    fi
    echo ""
    
    # If ForwardAuth is not working, provide manual instructions
    echo "=================================================="
    echo "MANUAL CONFIGURATION REQUIRED"
    echo "=================================================="
    echo ""
    
    if [[ "$setup_needed" == "true" ]]; then
        echo "1. COMPLETE INITIAL SETUP:"
        echo "   - Access: ${BASE_URL}/if/flow/initial-setup/"
        echo "   - Create user: akadmin"
        echo "   - Use password: ${ADMIN_PASSWORD}"
        echo "   - Use email: ${ADMIN_EMAIL}"
        echo ""
    fi
    
    echo "2. CONFIGURE PROXY PROVIDER:"
    echo "   - Access: ${BASE_URL}"
    echo "   - Login with: akadmin / ${ADMIN_PASSWORD}"
    echo "   - Go to: Applications -> Providers"
    echo "   - Click: Create"
    echo "   - Select: Proxy Provider"
    echo ""
    echo "   Provider Settings:"
    echo "   - Name: traefik-forwardauth"
    echo "   - Authorization flow: default-provider-authorization-explicit-consent"
    echo "   - Mode: Forward auth (single application)"
    echo "   - External host: https://auth.homelab.grenlan.com"
    echo "   - Internal host: http://192.168.1.13:9002"
    echo "   - Leave other fields as default"
    echo ""
    
    echo "3. CONFIGURE OUTPOST:"
    echo "   - Go to: Applications -> Outposts"
    echo "   - Find: 'authentik Embedded Outpost'"
    echo "   - Click: Edit"
    echo "   - In 'Selected providers': Add 'traefik-forwardauth'"
    echo "   - Click: Update"
    echo ""
    
    echo "4. VERIFY CONFIGURATION:"
    echo "   - Wait 30-60 seconds for outpost to restart"
    echo "   - Test endpoint: curl ${FORWARDAUTH_URL}"
    echo "   - Expected: HTTP 302 redirect or 200 OK"
    echo ""
    
    echo "5. TEST WITH TRAEFIK:"
    echo "   - The middleware is already configured in Traefik"
    echo "   - Apply it to services using: authentik-auth@file"
    echo ""
    
    echo "After completing these steps, run this script again to verify:"
    echo "  $0 $AUTHENTIK_HOST $ADMIN_PASSWORD"
    echo ""
}

# Run main function
main "$@"