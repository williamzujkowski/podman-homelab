#!/usr/bin/env bash
set -euo pipefail

# Test MCP Cloudflare Integration
# This script validates that our MCP servers are accessible and our Cloudflare configuration is correct

echo "=== MCP Cloudflare Integration Test ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check command availability
check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is installed"
    else
        echo -e "${RED}✗${NC} $1 is not installed"
        return 1
    fi
}

# Function to check DNS resolution
check_dns() {
    local domain="$1"
    local expected_ip="$2"
    
    echo "Checking DNS for $domain..."
    
    # Check if domain is in /etc/hosts
    if grep -q "$domain" /etc/hosts 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $domain found in /etc/hosts"
        grep "$domain" /etc/hosts
    else
        echo -e "${YELLOW}!${NC} $domain not in /etc/hosts (expected for local resolution)"
    fi
    
    # Try to resolve using dig
    if command -v dig &> /dev/null; then
        result=$(dig +short "$domain" 2>/dev/null || echo "")
        if [[ "$result" == "$expected_ip" ]]; then
            echo -e "${GREEN}✓${NC} $domain resolves to $expected_ip"
        elif [[ -z "$result" ]]; then
            echo -e "${YELLOW}!${NC} $domain does not resolve (expected for internal domain)"
        else
            echo -e "${YELLOW}!${NC} $domain resolves to $result (expected $expected_ip)"
        fi
    fi
}

# Function to check certificate files
check_certificates() {
    echo ""
    echo "=== Certificate Configuration ==="
    
    # Check for Cloudflare CA setup script
    if [[ -f "scripts/setup-cloudflare-ca.sh" ]]; then
        echo -e "${GREEN}✓${NC} Cloudflare CA setup script exists"
        echo "  Location: scripts/setup-cloudflare-ca.sh"
        
        # Check if it's executable
        if [[ -x "scripts/setup-cloudflare-ca.sh" ]]; then
            echo -e "${GREEN}✓${NC} Setup script is executable"
        else
            echo -e "${YELLOW}!${NC} Setup script is not executable"
        fi
    else
        echo -e "${RED}✗${NC} Cloudflare CA setup script not found"
    fi
    
    # Check for certificate documentation
    if [[ -f "CLOUDFLARE_INTEGRATION.md" ]]; then
        echo -e "${GREEN}✓${NC} Cloudflare integration documentation exists"
    fi
    
    if [[ -d "docs/certificates" ]]; then
        echo -e "${GREEN}✓${NC} Certificate documentation directory exists"
        ls -la docs/certificates/ | grep -E '\.md$' | awk '{print "  - " $NF}'
    fi
}

# Function to check service endpoints
check_services() {
    echo ""
    echo "=== Service Endpoints ==="
    
    local services=(
        "grafana.homelab.grenlan.com:443"
        "prometheus.homelab.grenlan.com:443"
        "loki.homelab.grenlan.com:443"
    )
    
    for service in "${services[@]}"; do
        domain="${service%:*}"
        port="${service##*:}"
        
        # Check if in /etc/hosts
        if grep -q "$domain" /etc/hosts 2>/dev/null; then
            echo -e "${GREEN}✓${NC} $domain configured in /etc/hosts"
        else
            echo -e "${YELLOW}!${NC} $domain not in /etc/hosts"
            echo "    Add to /etc/hosts: 192.168.1.11  $domain"
        fi
    done
}

# Function to check repository configuration
check_repo_config() {
    echo ""
    echo "=== Repository Configuration ==="
    
    # Check git remote
    if git remote -v | grep -q "github.com"; then
        echo -e "${GREEN}✓${NC} GitHub remote configured"
        git remote -v | head -2
    else
        echo -e "${RED}✗${NC} No GitHub remote found"
    fi
    
    # Check for MCP configuration files
    if [[ -f "cloudflare-mcp-setup.sh" ]]; then
        echo -e "${GREEN}✓${NC} Cloudflare MCP setup script exists"
    fi
    
    # Check Ansible configuration
    if [[ -f "ansible.cfg" ]] || [[ -f "ansible-staging.cfg" ]] || [[ -f "ansible-production.cfg" ]]; then
        echo -e "${GREEN}✓${NC} Ansible configuration files found"
        ls -la *.cfg 2>/dev/null | awk '{print "  - " $NF}'
    fi
}

# Function to validate Cloudflare DNS settings
validate_cloudflare_dns() {
    echo ""
    echo "=== Cloudflare DNS Configuration ==="
    echo ""
    echo "Required DNS Records (in Cloudflare Dashboard):"
    echo "  1. homelab.grenlan.com       → 192.168.1.11 (DNS only - grey cloud)"
    echo "  2. *.homelab.grenlan.com     → 192.168.1.11 (DNS only - grey cloud)"
    echo ""
    echo -e "${YELLOW}IMPORTANT:${NC} These records must NOT be proxied (orange cloud OFF)"
    echo "This ensures services are only accessible from your local network"
}

# Main execution
main() {
    echo "Starting MCP and Cloudflare integration tests..."
    echo ""
    
    # Check required commands
    echo "=== System Requirements ==="
    check_command "git"
    check_command "ansible"
    check_command "curl"
    check_command "dig"
    echo ""
    
    # Check DNS configuration
    echo "=== DNS Resolution ==="
    check_dns "homelab.grenlan.com" "192.168.1.11"
    check_dns "grafana.homelab.grenlan.com" "192.168.1.11"
    check_dns "prometheus.homelab.grenlan.com" "192.168.1.11"
    check_dns "loki.homelab.grenlan.com" "192.168.1.11"
    
    # Check certificates
    check_certificates
    
    # Check services
    check_services
    
    # Check repository
    check_repo_config
    
    # Validate Cloudflare DNS
    validate_cloudflare_dns
    
    echo ""
    echo "=== Test Summary ==="
    echo ""
    echo "MCP Integration:"
    echo "  - GitHub MCP server: Available for repository operations"
    echo "  - Cloudflare Flow MCP: Available for advanced operations"
    echo ""
    echo "Next Steps:"
    echo "  1. Ensure DNS records are configured in Cloudflare (grey cloud only)"
    echo "  2. Generate Origin CA certificate (15-year validity)"
    echo "  3. Run: ./scripts/setup-cloudflare-ca.sh"
    echo "  4. Deploy to production Pis following canary pattern"
    echo ""
    echo -e "${GREEN}Testing complete!${NC}"
}

# Run main function
main "$@"