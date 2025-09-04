#!/bin/bash
# Authentik Manual Configuration Guide with Verification
# =====================================================

set -euo pipefail

AUTHENTIK_HOST="${1:-192.168.1.13:9002}"
BASE_URL="http://${AUTHENTIK_HOST}"
ADMIN_PASSWORD="${2:-ChangeMe123!}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "${CYAN}"
    echo "============================================================"
    echo "$1"
    echo "============================================================"
    echo -e "${NC}"
}

print_step() {
    echo -e "${BLUE}📋 STEP $1: $2${NC}"
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
    echo -e "${YELLOW}💡 $1${NC}"
}

wait_for_input() {
    echo -e "${CYAN}Press Enter to continue after completing the step above...${NC}"
    read -r
}

test_endpoint() {
    local name="$1"
    local url="$2"
    local expected="$3"
    
    echo -n "   Testing $name... "
    local response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    
    case "$response" in
        $expected)
            echo -e "${GREEN}✅ Working (HTTP $response)${NC}"
            return 0
            ;;
        200|302|401)
            echo -e "${GREEN}✅ Working (HTTP $response)${NC}"
            return 0
            ;;
        404)
            echo -e "${RED}❌ Not Found (HTTP $response)${NC}"
            return 1
            ;;
        000)
            echo -e "${RED}❌ Connection Error${NC}"
            return 1
            ;;
        *)
            echo -e "${YELLOW}⚠️  Unexpected response (HTTP $response)${NC}"
            return 1
            ;;
    esac
}

# Main configuration process
print_header "AUTHENTIK MANUAL CONFIGURATION GUIDE"

echo "Target: $BASE_URL"
echo "Admin User: akadmin"
echo "Admin Password: $ADMIN_PASSWORD"
echo ""

# Test basic connectivity
print_step 1 "Testing Authentik Connectivity"
if ! test_endpoint "API" "${BASE_URL}/api/v3/root/config/" "200"; then
    print_error "Cannot connect to Authentik. Please check if the service is running."
    exit 1
fi
print_success "Authentik is accessible"

# Step 2: Initial Setup
print_step 2 "Initial Setup (if needed)"
echo ""
print_info "1. Open your web browser and navigate to:"
echo "   ${BASE_URL}/if/flow/initial-setup/"
echo ""
print_info "2. If you see a setup form, create the admin user:"
echo "   - Username: akadmin"
echo "   - Name: authentik Default Admin"  
echo "   - Email: admin@homelab.grenlan.com"
echo "   - Password: $ADMIN_PASSWORD"
echo "   - Confirm Password: $ADMIN_PASSWORD"
echo "   - Click 'Create'"
echo ""
print_info "3. If you see a login page or dashboard, setup is already complete"
echo ""
wait_for_input

# Step 3: Login to Admin Interface
print_step 3 "Admin Interface Login"
echo ""
print_info "1. Navigate to the admin interface:"
echo "   ${BASE_URL}/if/admin/"
echo ""
print_info "2. Login with:"
echo "   - Username: akadmin"
echo "   - Password: $ADMIN_PASSWORD"
echo ""
print_info "3. You should see the Authentik administration dashboard"
echo ""
wait_for_input

# Step 4: Create ForwardAuth Provider
print_step 4 "Create ForwardAuth Provider"
echo ""
print_warning "This is the MOST IMPORTANT step for Traefik integration!"
echo ""
print_info "1. In the admin interface, click on 'Applications' in the sidebar"
print_info "2. Click on 'Providers'"
print_info "3. Click the 'Create' button (usually a '+' or 'Create' button)"
print_info "4. Select 'Proxy Provider'"
print_info "5. Fill out the form with EXACTLY these values:"
echo ""
echo "   Name: traefik-forwardauth"
echo "   Authorization flow: default-provider-authorization-explicit-consent"
echo "   Mode: Forward auth (single application)"
echo "   External host: https://auth.homelab.grenlan.com"
echo "   Internal host: http://192.168.1.13:9002"
echo "   Cookie domain: homelab.grenlan.com"
echo ""
print_info "6. Click 'Create' or 'Save'"
echo ""
print_warning "Make sure the Mode is set to 'Forward auth (single application)' - this is critical!"
echo ""
wait_for_input

# Step 5: Configure Embedded Outpost
print_step 5 "Configure Embedded Outpost"
echo ""
print_info "1. In the admin interface, go to 'Applications' → 'Outposts'"
print_info "2. You should see 'authentik Embedded Outpost' in the list"
print_info "3. Click on it to edit"
print_info "4. In the 'Selected providers' section:"
print_info "   - Look for 'traefik-forwardauth' in the available providers"
print_info "   - Select/check the 'traefik-forwardauth' provider"
print_info "   - Make sure it appears in the 'Selected' section"
print_info "5. Click 'Update' or 'Save'"
print_info "6. The outpost should automatically restart (this may take 30-60 seconds)"
echo ""
print_warning "Wait for the outpost to restart before continuing!"
echo ""
wait_for_input

# Step 6: Test ForwardAuth Endpoint
print_step 6 "Test ForwardAuth Endpoint"
echo ""
print_info "Testing the ForwardAuth endpoint..."
sleep 5  # Give outpost time to start

if test_endpoint "ForwardAuth" "${BASE_URL}/outpost.goauthentik.io/auth/traefik" "302"; then
    print_success "ForwardAuth endpoint is working!"
    FORWARDAUTH_WORKING=true
else
    print_error "ForwardAuth endpoint is not working"
    echo ""
    print_warning "Troubleshooting steps:"
    echo "1. Verify the provider was created correctly"
    echo "2. Check that the outpost includes the provider"
    echo "3. Wait longer for outpost restart (try 2-3 minutes)"
    echo "4. Check Authentik container logs: ssh pi@192.168.1.13 'sudo podman logs authentik-server'"
    echo ""
    read -p "Do you want to continue with OAuth2 setup anyway? (y/N): " -r continue_anyway
    if [[ ! $continue_anyway =~ ^[Yy]$ ]]; then
        print_error "Please fix the ForwardAuth issue before continuing"
        exit 1
    fi
    FORWARDAUTH_WORKING=false
fi

# Step 7: Create OAuth2 Provider for Grafana
print_step 7 "Create OAuth2 Provider for Grafana"
echo ""
print_info "1. Go back to 'Applications' → 'Providers'"
print_info "2. Click 'Create'"
print_info "3. Select 'OAuth2/OpenID Provider'"
print_info "4. Fill out the form:"
echo ""
echo "   Name: grafana-oauth2"
echo "   Authorization flow: default-provider-authorization-explicit-consent"
echo "   Client type: Confidential"
echo "   Client ID: grafana"
echo "   Client Secret: [Click 'Generate' button and COPY THE SECRET!]"
echo "   Redirect URIs: http://192.168.1.12:3000/login/generic_oauth"
echo ""
print_warning "IMPORTANT: Copy the generated Client Secret! You'll need it for Grafana configuration."
print_info "5. Click 'Create'"
echo ""
wait_for_input

# Step 8: Create Grafana Application
print_step 8 "Create Grafana Application"
echo ""
print_info "1. Go to 'Applications' → 'Applications'"
print_info "2. Click 'Create'"
print_info "3. Fill out the form:"
echo ""
echo "   Name: Grafana"
echo "   Slug: grafana"
echo "   Provider: grafana-oauth2 (select from dropdown)"
echo "   Launch URL: http://192.168.1.12:3000"
echo ""
print_info "4. Click 'Create'"
echo ""
wait_for_input

# Step 9: Final Verification
print_step 9 "Final Verification"
echo ""
print_info "Testing all endpoints..."

echo ""
echo "Endpoint Test Results:"
echo "======================"

# Test ForwardAuth
if test_endpoint "ForwardAuth" "${BASE_URL}/outpost.goauthentik.io/auth/traefik" "302"; then
    FORWARDAUTH_OK=true
else
    FORWARDAUTH_OK=false
fi

# Test OAuth2 endpoints
test_endpoint "OAuth2 Authorization" "${BASE_URL}/application/o/authorize/" "404" && OAUTH_AUTH_OK=true || OAUTH_AUTH_OK=false
test_endpoint "OAuth2 Token" "${BASE_URL}/application/o/token/" "405" && OAUTH_TOKEN_OK=true || OAUTH_TOKEN_OK=false  
test_endpoint "OAuth2 UserInfo" "${BASE_URL}/application/o/userinfo/" "401" && OAUTH_USER_OK=true || OAUTH_USER_OK=false

# Summary
print_header "CONFIGURATION SUMMARY"

if [[ "$FORWARDAUTH_OK" == true ]]; then
    print_success "ForwardAuth Configuration: COMPLETE ✅"
    echo ""
    echo "🎯 Traefik can now use ForwardAuth middleware:"
    echo "   middlewares:"
    echo "     - authentik-auth@file"
    echo ""
    echo "📍 ForwardAuth URL: ${BASE_URL}/outpost.goauthentik.io/auth/traefik"
else
    print_error "ForwardAuth Configuration: INCOMPLETE ❌"
    echo ""
    echo "⚠️  Please review the provider and outpost configuration"
fi

echo ""
if [[ "$OAUTH_TOKEN_OK" == true ]]; then
    print_success "OAuth2 Configuration: READY FOR GRAFANA ✅"
    echo ""
    echo "📍 OAuth2 Endpoints:"
    echo "   - Authorization: ${BASE_URL}/application/o/authorize/"
    echo "   - Token: ${BASE_URL}/application/o/token/"
    echo "   - UserInfo: ${BASE_URL}/application/o/userinfo/"
else
    print_warning "OAuth2 Configuration: NEEDS VERIFICATION ⚠️"
    echo "   Some OAuth2 endpoints may not be fully configured"
fi

# Create configuration file
CONFIG_FILE="/tmp/authentik-manual-config-$(date +%Y%m%d-%H%M%S).txt"
cat > "$CONFIG_FILE" << EOF
Authentik Manual Configuration Results
======================================
Date: $(date)
Base URL: ${BASE_URL}
Admin User: akadmin
Admin Password: ${ADMIN_PASSWORD}

ForwardAuth Status: $(if [[ "$FORWARDAUTH_OK" == true ]]; then echo "WORKING"; else echo "FAILED"; fi)
OAuth2 Status: $(if [[ "$OAUTH_TOKEN_OK" == true ]]; then echo "CONFIGURED"; else echo "NEEDS_WORK"; fi)

Providers Created:
- traefik-forwardauth (Proxy Provider)
- grafana-oauth2 (OAuth2/OpenID Provider)

Applications Created:
- Grafana (using grafana-oauth2 provider)

Next Steps:
1. Configure Grafana OAuth2 integration
2. Test authentication flow
3. Set up user groups and permissions

Important URLs:
- ForwardAuth: ${BASE_URL}/outpost.goauthentik.io/auth/traefik
- OAuth2 Auth: ${BASE_URL}/application/o/authorize/
- OAuth2 Token: ${BASE_URL}/application/o/token/
- OAuth2 UserInfo: ${BASE_URL}/application/o/userinfo/

Grafana OAuth2 Configuration:
- Client ID: grafana
- Client Secret: [FROM AUTHENTIK - COPY WHEN CREATING PROVIDER]
- Auth URL: ${BASE_URL}/application/o/authorize/
- Token URL: ${BASE_URL}/application/o/token/
- API URL: ${BASE_URL}/application/o/userinfo/
- Redirect URI: http://192.168.1.12:3000/login/generic_oauth
EOF

echo ""
print_info "Configuration details saved to: $CONFIG_FILE"

echo ""
print_header "NEXT STEPS"

echo "1. 📝 Copy the OAuth2 Client Secret from Authentik"
echo "2. 🔧 Configure Grafana OAuth2 (see ansible/playbooks/52-grafana-oauth2.yml)"
echo "3. 🧪 Test the complete authentication flow"
echo "4. 👥 Create user groups in Authentik for role mapping"
echo ""

if [[ "$FORWARDAUTH_OK" == true ]]; then
    echo "🎉 ForwardAuth is ready! You can now protect services with Traefik middleware."
else
    echo "⚠️  Please fix ForwardAuth configuration before proceeding to protect services."
fi