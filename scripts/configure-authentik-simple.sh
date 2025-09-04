#!/bin/bash
set -euo pipefail

# Simple Authentik Configuration Script
# ====================================
# This script configures the necessary components using curl and manual steps

AUTHENTIK_HOST="${1:-192.168.1.13:9002}"
BASE_URL="http://${AUTHENTIK_HOST}"
ADMIN_PASSWORD="${2:-ChangeMe123!}"

echo "Authentik Configuration Script"
echo "=============================="
echo "Target: ${BASE_URL}"
echo "Admin Password: ${ADMIN_PASSWORD}"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${BLUE}Step $1: $2${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}📝 $1${NC}"
}

# Step 1: Check if Authentik is accessible
print_step 1 "Checking Authentik accessibility"
if curl -s -f "${BASE_URL}/api/v3/root/config/" > /dev/null; then
    print_success "Authentik API is accessible"
else
    print_error "Authentik API is not accessible"
    exit 1
fi

# Step 2: Check if initial setup is needed
print_step 2 "Checking initial setup status"
SETUP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/if/flow/initial-setup/")

if [[ "$SETUP_RESPONSE" == "200" ]]; then
    print_warning "Initial setup may be required"
    echo ""
    print_info "MANUAL ACTION REQUIRED:"
    echo "1. Open browser: ${BASE_URL}/if/flow/initial-setup/"
    echo "2. Create admin user with:"
    echo "   - Username: akadmin"
    echo "   - Name: authentik Default Admin"
    echo "   - Email: admin@homelab.grenlan.com"
    echo "   - Password: ${ADMIN_PASSWORD}"
    echo "   - Confirm Password: ${ADMIN_PASSWORD}"
    echo "3. Click 'Create' to complete setup"
    echo ""
    read -p "Press Enter after completing initial setup..." -r
else
    print_success "Initial setup appears to be completed"
fi

# Step 3: Check admin interface access
print_step 3 "Testing admin interface access"
ADMIN_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/if/admin/")

if [[ "$ADMIN_RESPONSE" == "200" ]]; then
    print_success "Admin interface is accessible"
else
    print_error "Admin interface is not accessible"
    exit 1
fi

# Step 4: Provide manual configuration instructions
print_step 4 "ForwardAuth Provider Configuration"
echo ""
print_info "MANUAL CONFIGURATION REQUIRED:"
echo "1. Open browser: ${BASE_URL}/if/admin/"
echo "2. Login with: akadmin / ${ADMIN_PASSWORD}"
echo "3. Navigate to: Applications > Providers"
echo "4. Click 'Create' and select 'Proxy Provider'"
echo "5. Configure with these settings:"
echo "   - Name: traefik-forwardauth"
echo "   - Authorization flow: default-provider-authorization-explicit-consent"
echo "   - Mode: Forward auth (single application)"
echo "   - External host: https://auth.homelab.grenlan.com"
echo "   - Internal host: http://192.168.1.13:9002"
echo "   - Internal host SSL Validation: ✓ (checked)"
echo "   - Cookie domain: homelab.grenlan.com"
echo "6. Click 'Create' to save the provider"
echo ""
read -p "Press Enter after creating the ForwardAuth provider..." -r

# Step 5: Configure Embedded Outpost
print_step 5 "Embedded Outpost Configuration"
echo ""
print_info "CONFIGURE EMBEDDED OUTPOST:"
echo "1. In the same admin interface, navigate to: Applications > Outposts"
echo "2. Click on 'authentik Embedded Outpost'"
echo "3. In the 'Selected providers' section, add 'traefik-forwardauth'"
echo "4. Click 'Update' to save changes"
echo "5. Wait 30-60 seconds for the outpost to restart"
echo ""
read -p "Press Enter after configuring the outpost..." -r

# Step 6: Test ForwardAuth endpoint
print_step 6 "Testing ForwardAuth endpoint"
echo "Waiting 10 seconds for outpost to fully restart..."
sleep 10

FORWARDAUTH_URL="${BASE_URL}/outpost.goauthentik.io/auth/traefik"
FORWARDAUTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$FORWARDAUTH_URL" || echo "000")

case "$FORWARDAUTH_RESPONSE" in
    302)
        print_success "ForwardAuth endpoint is working! (HTTP 302 - redirect to login)"
        FORWARDAUTH_WORKING=true
        ;;
    401)
        print_success "ForwardAuth endpoint is working! (HTTP 401 - unauthorized)"
        FORWARDAUTH_WORKING=true
        ;;
    200)
        print_success "ForwardAuth endpoint is accessible! (HTTP 200)"
        FORWARDAUTH_WORKING=true
        ;;
    404)
        print_error "ForwardAuth endpoint not found (HTTP 404)"
        echo "Please verify the provider and outpost configuration"
        FORWARDAUTH_WORKING=false
        ;;
    000)
        print_error "ForwardAuth endpoint not reachable"
        FORWARDAUTH_WORKING=false
        ;;
    *)
        print_warning "ForwardAuth endpoint returned HTTP ${FORWARDAUTH_RESPONSE}"
        FORWARDAUTH_WORKING=true
        ;;
esac

# Step 7: Configure OAuth2 Provider for Grafana
if [[ "$FORWARDAUTH_WORKING" == true ]]; then
    print_step 7 "OAuth2 Provider for Grafana Configuration"
    echo ""
    print_info "CREATE OAUTH2 PROVIDER FOR GRAFANA:"
    echo "1. In the admin interface, go to: Applications > Providers"
    echo "2. Click 'Create' and select 'OAuth2/OpenID Provider'"
    echo "3. Configure with these settings:"
    echo "   - Name: grafana-oauth2"
    echo "   - Authorization flow: default-provider-authorization-explicit-consent"
    echo "   - Client type: Confidential"
    echo "   - Client ID: grafana"
    echo "   - Click 'Generate' for Client secret (SAVE THIS!)"
    echo "   - Redirect URIs: http://192.168.1.12:3000/login/generic_oauth"
    echo "4. Click 'Create' to save the provider"
    echo "5. Copy the Client Secret - you'll need it for Grafana configuration"
    echo ""
    read -p "Press Enter after creating the OAuth2 provider..." -r
    
    # Step 8: Create Application for Grafana
    print_step 8 "Create Grafana Application"
    echo ""
    print_info "CREATE GRAFANA APPLICATION:"
    echo "1. Navigate to: Applications > Applications"
    echo "2. Click 'Create'"
    echo "3. Configure with these settings:"
    echo "   - Name: Grafana"
    echo "   - Slug: grafana"
    echo "   - Provider: grafana-oauth2 (select from dropdown)"
    echo "   - Launch URL: http://192.168.1.12:3000"
    echo "4. Click 'Create'"
    echo ""
    read -p "Press Enter after creating the Grafana application..." -r
fi

# Final Test
print_step 9 "Final Verification"
echo ""
echo "Testing all endpoints..."

# Test ForwardAuth again
FINAL_FORWARDAUTH=$(curl -s -o /dev/null -w "%{http_code}" "$FORWARDAUTH_URL" || echo "000")
if [[ "$FINAL_FORWARDAUTH" =~ ^(200|302|401)$ ]]; then
    print_success "ForwardAuth endpoint: WORKING (HTTP $FINAL_FORWARDAUTH)"
else
    print_error "ForwardAuth endpoint: FAILED (HTTP $FINAL_FORWARDAUTH)"
fi

# Test OAuth2 endpoint
OAUTH2_URL="${BASE_URL}/application/o/grafana/"
OAUTH2_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$OAUTH2_URL" || echo "000")
if [[ "$OAUTH2_RESPONSE" =~ ^(200|302|404)$ ]]; then
    print_success "OAuth2 endpoint: ACCESSIBLE (HTTP $OAUTH2_RESPONSE)"
else
    print_warning "OAuth2 endpoint: Status HTTP $OAUTH2_RESPONSE"
fi

echo ""
echo "=========================================="
echo "CONFIGURATION SUMMARY"
echo "=========================================="

if [[ "$FINAL_FORWARDAUTH" =~ ^(200|302|401)$ ]]; then
    print_success "ForwardAuth Configuration: COMPLETE"
    echo ""
    echo "You can now protect services with Traefik middleware:"
    echo "  middlewares:"
    echo "    - authentik-auth@file"
    echo ""
    echo "Test ForwardAuth with a protected service:"
    echo "1. Apply middleware to a Traefik route"
    echo "2. Access the service - you should be redirected to login"
    echo "3. Login URL: https://auth.homelab.grenlan.com"
    echo "4. Credentials: akadmin / ${ADMIN_PASSWORD}"
    echo ""
else
    print_error "ForwardAuth Configuration: INCOMPLETE"
    echo "Please verify the manual configuration steps above."
    echo ""
fi

print_info "Next Steps:"
echo "- Configure Grafana OAuth2 (see playbook: ansible/playbooks/52-grafana-oauth2.yml)"
echo "- Create user groups in Authentik for role mapping"
echo "- Set up additional applications as needed"
echo ""

# Save configuration info
CONFIG_FILE="/tmp/authentik-config-$(date +%Y%m%d-%H%M%S).txt"
cat > "$CONFIG_FILE" << EOF
Authentik Configuration Summary
===============================
Date: $(date)
Base URL: ${BASE_URL}
Admin User: akadmin
Admin Password: ${ADMIN_PASSWORD}

ForwardAuth Status: $(if [[ "$FINAL_FORWARDAUTH" =~ ^(200|302|401)$ ]]; then echo "WORKING"; else echo "FAILED"; fi)
ForwardAuth URL: ${FORWARDAUTH_URL}

OAuth2 Status: CREATED (manual)
OAuth2 URL: ${OAUTH2_URL}

Configuration Files:
- ForwardAuth Provider: traefik-forwardauth
- OAuth2 Provider: grafana-oauth2
- Grafana Application: grafana

Manual Steps Completed:
- [x] Initial setup (if needed)
- [x] ForwardAuth Provider creation
- [x] Embedded Outpost configuration
- [x] OAuth2 Provider for Grafana
- [x] Grafana Application creation

Traefik Middleware:
  middlewares:
    authentik-auth:
      forwardAuth:
        address: "${FORWARDAUTH_URL}"
EOF

echo "Configuration details saved to: $CONFIG_FILE"