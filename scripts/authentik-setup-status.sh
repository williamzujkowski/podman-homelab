#!/bin/bash
set -euo pipefail

# Authentik Setup Status Checker
# ===============================
# Checks current status and provides next steps

AUTHENTIK_HOST="${1:-192.168.1.13:9002}"
BASE_URL="http://${AUTHENTIK_HOST}"

echo "Authentik Setup Status Check"
echo "============================="
echo "Target: ${BASE_URL}"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    local icon=$1
    local color=$2
    local message=$3
    echo -e "${color}${icon} ${message}${NC}"
}

# Check 1: Initial setup status
echo "🔍 Checking initial setup status..."
initial_setup_response=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/if/flow/initial-setup/" || echo "000")

if [[ "$initial_setup_response" == "200" ]]; then
    print_status "⚠️ " "$YELLOW" "Initial setup is REQUIRED"
    initial_setup_needed=true
elif [[ "$initial_setup_response" == "302" ]] || [[ "$initial_setup_response" == "404" ]]; then
    print_status "✅" "$GREEN" "Initial setup is COMPLETED"
    initial_setup_needed=false
else
    print_status "❓" "$RED" "Initial setup status unclear (HTTP $initial_setup_response)"
    initial_setup_needed=true
fi

echo ""

# Check 2: ForwardAuth endpoint
echo "🔍 Checking ForwardAuth endpoint..."
forwardauth_response=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/outpost.goauthentik.io/auth/traefik" || echo "000")

if [[ "$forwardauth_response" == "404" ]]; then
    print_status "❌" "$RED" "ForwardAuth endpoint NOT configured"
    forwardauth_working=false
elif [[ "$forwardauth_response" =~ ^(200|302|401)$ ]]; then
    print_status "✅" "$GREEN" "ForwardAuth endpoint is WORKING"
    forwardauth_working=true
else
    print_status "❓" "$YELLOW" "ForwardAuth endpoint status unclear (HTTP $forwardauth_response)"
    forwardauth_working=false
fi

echo ""

# Check 3: Container health
echo "🔍 Checking container status..."
if ssh -o ConnectTimeout=3 pi@192.168.1.13 "echo 'OK'" &>/dev/null; then
    containers=$(ssh pi@192.168.1.13 "sudo podman ps --format '{{.Names}} {{.Status}}' | grep authentik" || echo "")
    
    if echo "$containers" | grep -q "authentik-server.*healthy"; then
        print_status "✅" "$GREEN" "Server container is healthy"
    elif echo "$containers" | grep -q "authentik-server.*unhealthy"; then
        print_status "⚠️ " "$YELLOW" "Server container is unhealthy"
    elif echo "$containers" | grep -q "authentik-server"; then
        print_status "⚠️ " "$YELLOW" "Server container is running"
    else
        print_status "❌" "$RED" "Server container not found"
    fi
    
    if echo "$containers" | grep -q "authentik-worker.*healthy"; then
        print_status "✅" "$GREEN" "Worker container is healthy"
    else
        print_status "❓" "$YELLOW" "Worker container status unknown"
    fi
else
    print_status "❌" "$RED" "Cannot connect to host"
fi

echo ""

# Provide next steps based on status
echo "========================================="
echo "NEXT STEPS"
echo "========================================="

if [[ "$forwardauth_working" == true ]]; then
    print_status "🎉" "$GREEN" "Authentik ForwardAuth is fully configured!"
    echo ""
    echo "You can now protect services with Traefik middleware:"
    echo ""
    echo -e "${BLUE}middlewares:${NC}"
    echo -e "${BLUE}  - authentik-auth@file${NC}"
    echo ""
    echo "Test the authentication:"
    echo "1. Apply middleware to a service"
    echo "2. Access the service URL"
    echo "3. Should redirect to: https://auth.homelab.grenlan.com"
    echo ""
    
elif [[ "$initial_setup_needed" == true ]]; then
    print_status "📋" "$BLUE" "Complete initial setup first"
    echo ""
    echo "Step 1: Complete Initial Setup"
    echo "------------------------------"
    echo "🌐 Access: ${BASE_URL}/if/flow/initial-setup/"
    echo "👤 Username: akadmin"
    echo "📧 Email: admin@homelab.grenlan.com"
    echo "🔒 Password: ChangeMe123!"
    echo ""
    echo "After completing initial setup, run this script again."
    
else
    print_status "📋" "$BLUE" "Configure ForwardAuth provider and outpost"
    echo ""
    echo "Step 1: Login to Admin Interface"
    echo "--------------------------------"
    echo "🌐 Access: ${BASE_URL}"
    echo "👤 Username: akadmin"
    echo "🔒 Password: ChangeMe123!"
    echo ""
    
    echo "Step 2: Create Proxy Provider"
    echo "-----------------------------"
    echo "1. Go to: Applications → Providers"
    echo "2. Click: Create → Proxy Provider"
    echo "3. Configuration:"
    echo "   • Name: traefik-forwardauth"
    echo "   • Mode: Forward auth (single application)"
    echo "   • External host: https://auth.homelab.grenlan.com"
    echo "   • Internal host: http://192.168.1.13:9002"
    echo "   • Cookie domain: homelab.grenlan.com"
    echo ""
    
    echo "Step 3: Configure Outpost"
    echo "------------------------"
    echo "1. Go to: Applications → Outposts"
    echo "2. Edit: 'authentik Embedded Outpost'"
    echo "3. Add provider: 'traefik-forwardauth'"
    echo "4. Save and wait for restart"
    echo ""
    
    echo "Step 4: Verify Configuration"
    echo "----------------------------"
    echo "Run test script:"
    echo "/home/william/git/podman-homelab/scripts/test-authentik-forwardauth.sh"
fi

echo ""
echo "========================================="
echo "DOCUMENTATION"
echo "========================================="
echo "📚 Full guide: /home/william/git/podman-homelab/docs/authentik-forwardauth-configuration.md"
echo "🧪 Test script: /home/william/git/podman-homelab/scripts/test-authentik-forwardauth.sh"
echo "⚙️  Config script: /home/william/git/podman-homelab/scripts/configure-authentik-forwardauth.sh"
echo ""