#!/bin/bash
# Tailscale Setup for Redundant SSH Access
# Provides secondary SSH access path when primary network fails

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration - YOU MUST SET THIS!
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/pi_ed25519}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Tailscale Redundancy Setup${NC}"
echo -e "${GREEN}========================================${NC}"

# Check for auth key
if [ -z "$TAILSCALE_AUTH_KEY" ]; then
    echo -e "${YELLOW}No Tailscale auth key provided.${NC}"
    echo ""
    echo "To enable Tailscale redundancy:"
    echo "1. Go to https://login.tailscale.com/admin/settings/authkeys"
    echo "2. Generate a new auth key (reusable, pre-approved)"
    echo "3. Run: export TAILSCALE_AUTH_KEY='tskey-auth-...'"
    echo "4. Re-run this script"
    echo ""
    echo "Benefits of Tailscale redundancy:"
    echo "  • Access Pis from anywhere (WireGuard VPN)"
    echo "  • Works even if local network fails"
    echo "  • Automatic NAT traversal"
    echo "  • Built-in SSH (no port forwarding needed)"
    echo "  • MagicDNS for easy naming"
    exit 0
fi

# Function to install Tailscale on Pi
install_tailscale_on_pi() {
    local hostname="$1"
    
    echo -e "\n${YELLOW}Installing Tailscale on $hostname...${NC}"
    
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$hostname" << EOSSH
#!/bin/bash
set -e

# Check if already installed
if command -v tailscale &>/dev/null; then
    echo "  Tailscale already installed"
    
    # Check if already connected
    if tailscale status &>/dev/null; then
        echo "  Already connected to Tailnet"
        tailscale status | head -5
        exit 0
    fi
else
    echo "  Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sudo sh
fi

# Configure and start Tailscale
echo "  Connecting to Tailnet..."
sudo tailscale up \
    --authkey "$TAILSCALE_AUTH_KEY" \
    --hostname "\$(hostname)" \
    --ssh \
    --accept-routes \
    --accept-dns=false \
    --advertise-tags=tag:pi

# Wait for connection
sleep 5

# Get Tailscale IP
TS_IP=\$(tailscale ip -4 2>/dev/null || echo "Not connected")
echo "  Tailscale IP: \$TS_IP"

# Enable Tailscale SSH
sudo tailscale set --ssh

# Show status
tailscale status | head -5
EOSSH
    
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✓ Tailscale installed on $hostname${NC}"
        return 0
    else
        echo -e "  ${RED}✗ Failed to install on $hostname${NC}"
        return 1
    fi
}

# Function to get Tailscale IPs
get_tailscale_ips() {
    echo -e "\n${YELLOW}Getting Tailscale IPs...${NC}"
    
    for hostname in pi-a pi-b pi-c pi-d; do
        echo -n "  $hostname: "
        
        # Get Tailscale IP from the Pi
        ts_ip=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$SSH_KEY" "$hostname" \
            "tailscale ip -4 2>/dev/null" 2>/dev/null || echo "")
        
        if [ -n "$ts_ip" ]; then
            echo -e "${GREEN}$ts_ip${NC}"
            echo "$hostname $ts_ip" >> tailscale-ips.txt
        else
            echo -e "${YELLOW}Not connected${NC}"
        fi
    done
}

# Function to create Tailscale SSH config
create_tailscale_ssh_config() {
    echo -e "\n${YELLOW}Creating Tailscale SSH config...${NC}"
    
    cat > "$HOME/.ssh/config.d/pi-cluster-tailscale" << 'EOF'
# Tailscale redundant SSH access for Pi cluster
# This provides backup access if primary network fails

# Primary access via local network (preferred)
Host pi-a
    HostName pi-a.local
    User pi
    IdentityFile ~/.ssh/pi_ed25519
    StrictHostKeyChecking no
    ConnectTimeout 5
    ProxyCommand sh -c 'if nc -z %h %p 2>/dev/null; then nc %h %p; else ssh pi-a-ts nc localhost %p; fi'

Host pi-b
    HostName pi-b.local
    User pi
    IdentityFile ~/.ssh/pi_ed25519
    StrictHostKeyChecking no
    ConnectTimeout 5
    ProxyCommand sh -c 'if nc -z %h %p 2>/dev/null; then nc %h %p; else ssh pi-b-ts nc localhost %p; fi'

Host pi-c
    HostName pi-c.local
    User pi
    IdentityFile ~/.ssh/pi_ed25519
    StrictHostKeyChecking no
    ConnectTimeout 5
    ProxyCommand sh -c 'if nc -z %h %p 2>/dev/null; then nc %h %p; else ssh pi-c-ts nc localhost %p; fi'

Host pi-d
    HostName pi-d.local
    User pi
    IdentityFile ~/.ssh/pi_ed25519
    StrictHostKeyChecking no
    ConnectTimeout 5
    ProxyCommand sh -c 'if nc -z %h %p 2>/dev/null; then nc %h %p; else ssh pi-d-ts nc localhost %p; fi'

# Tailscale direct access (backup)
Host pi-a-ts
    HostName pi-a
    User pi
    IdentityFile ~/.ssh/pi_ed25519
    StrictHostKeyChecking no
    ProxyCommand tailscale nc %h %p

Host pi-b-ts
    HostName pi-b
    User pi
    IdentityFile ~/.ssh/pi_ed25519
    StrictHostKeyChecking no
    ProxyCommand tailscale nc %h %p

Host pi-c-ts
    HostName pi-c
    User pi
    IdentityFile ~/.ssh/pi_ed25519
    StrictHostKeyChecking no
    ProxyCommand tailscale nc %h %p

Host pi-d-ts
    HostName pi-d
    User pi
    IdentityFile ~/.ssh/pi_ed25519
    StrictHostKeyChecking no
    ProxyCommand tailscale nc %h %p
EOF
    
    echo -e "${GREEN}✓ Tailscale SSH config created${NC}"
}

# Function to test redundancy
test_redundancy() {
    echo -e "\n${YELLOW}Testing redundancy...${NC}"
    
    for hostname in pi-a pi-b pi-c pi-d; do
        echo -e "\n  Testing $hostname:"
        
        # Test primary access
        echo -n "    Primary (local): "
        if timeout 5 ssh -o ConnectTimeout=3 "$hostname" "echo OK" &>/dev/null; then
            echo -e "${GREEN}✓ Working${NC}"
        else
            echo -e "${RED}✗ Failed${NC}"
        fi
        
        # Test Tailscale access
        echo -n "    Tailscale: "
        if timeout 5 ssh -o ConnectTimeout=3 "${hostname}-ts" "echo OK" &>/dev/null; then
            echo -e "${GREEN}✓ Working${NC}"
        else
            echo -e "${YELLOW}✗ Not available${NC}"
        fi
    done
}

# Main execution
main() {
    # Check if Tailscale is installed locally
    if ! command -v tailscale &>/dev/null; then
        echo -e "${YELLOW}Installing Tailscale on local machine...${NC}"
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    
    # Connect local machine to Tailscale if not already
    if ! tailscale status &>/dev/null; then
        echo -e "${YELLOW}Connecting local machine to Tailscale...${NC}"
        echo "Please login when browser opens..."
        sudo tailscale up --ssh
    fi
    
    # Install on all Pis
    echo -e "\n${YELLOW}Installing Tailscale on all Pis...${NC}"
    for hostname in pi-a pi-b pi-c pi-d; do
        install_tailscale_on_pi "$hostname" || true
    done
    
    # Get Tailscale IPs
    get_tailscale_ips
    
    # Create SSH config
    create_tailscale_ssh_config
    
    # Test redundancy
    test_redundancy
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}   Tailscale Redundancy Setup Complete${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "You now have redundant SSH access:"
    echo "  • Primary: Local network (DHCP)"
    echo "  • Backup: Tailscale VPN"
    echo ""
    echo "Access methods:"
    echo "  ssh pi-a         # Auto-failover"
    echo "  ssh pi-a-ts      # Force Tailscale"
    echo ""
    echo "Tailscale features enabled:"
    echo "  • SSH access from anywhere"
    echo "  • Works behind NAT/firewalls"
    echo "  • Encrypted WireGuard tunnel"
    echo "  • MagicDNS for easy naming"
    echo ""
    echo "Monitor status:"
    echo "  tailscale status"
    echo "  tailscale ping pi-a"
}

# Run main
main "$@"