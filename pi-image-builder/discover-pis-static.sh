#!/bin/bash
# Optimized Pi Discovery for Static DHCP Leases
# Checks known static IPs first, then falls back to discovery

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
STATIC_CONFIG="static-dhcp-config.json"
ANSIBLE_INVENTORY="../ansible/inventories/prod/hosts.yml"
DISCOVERY_FILE="discovered-pis.json"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/pi_ed25519}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Pi Discovery (Static DHCP Mode)${NC}"
echo -e "${BLUE}========================================${NC}"

# Function to test known static IP
test_static_ip() {
    local hostname="$1"
    local ip="$2"
    local expected_mac="$3"
    
    echo -n "  Testing $hostname at $ip..."
    
    # Quick ping test
    if ping -c 1 -W 1 "$ip" &>/dev/null; then
        # Verify it's actually our Pi
        actual_hostname=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 -i "$SSH_KEY" \
            "pi@$ip" "hostname" 2>/dev/null || echo "unknown")
        
        if [ "$actual_hostname" = "$hostname" ]; then
            # Get MAC address
            mac=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 -i "$SSH_KEY" \
                "pi@$ip" "ip link show eth0 | grep 'link/ether' | awk '{print \$2}'" 2>/dev/null || echo "")
            
            if [ -n "$mac" ]; then
                echo -e " ${GREEN}✓ OK (MAC: $mac)${NC}"
                
                # Update static config if MAC changed
                if [ "$expected_mac" = "PENDING" ] || [ "$expected_mac" != "$mac" ]; then
                    echo "    Updating MAC address in config..."
                    jq ".static_leases.\"$hostname\".mac = \"$mac\"" "$STATIC_CONFIG" > "${STATIC_CONFIG}.tmp"
                    mv "${STATIC_CONFIG}.tmp" "$STATIC_CONFIG"
                fi
                
                # Add to discovery results
                echo "{\"hostname\":\"$hostname\",\"ip\":\"$ip\",\"mac\":\"$mac\",\"method\":\"static\",\"verified\":true}" >> "$DISCOVERY_FILE.tmp"
                return 0
            else
                echo -e " ${YELLOW}⚠ Connected but couldn't get MAC${NC}"
                echo "{\"hostname\":\"$hostname\",\"ip\":\"$ip\",\"mac\":\"unknown\",\"method\":\"static\",\"verified\":false}" >> "$DISCOVERY_FILE.tmp"
                return 0
            fi
        else
            echo -e " ${YELLOW}⚠ Wrong hostname (got: $actual_hostname)${NC}"
            return 1
        fi
    else
        echo -e " ${RED}✗ Not responding${NC}"
        return 1
    fi
}

# Function to discover via fallback methods
discover_fallback() {
    local hostname="$1"
    
    echo "  Searching for $hostname via other methods..."
    
    # Try mDNS
    local ip=""
    if command -v avahi-resolve &>/dev/null; then
        ip=$(avahi-resolve -n "${hostname}.local" 2>/dev/null | awk '{print $2}')
    fi
    
    if [ -z "$ip" ]; then
        ip=$(getent hosts "${hostname}.local" 2>/dev/null | awk '{print $1}')
    fi
    
    if [ -n "$ip" ]; then
        echo "    Found via mDNS at $ip"
        
        # Get MAC
        mac=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 -i "$SSH_KEY" \
            "pi@$ip" "ip link show eth0 | grep 'link/ether' | awk '{print \$2}'" 2>/dev/null || echo "")
        
        if [ -n "$mac" ]; then
            echo "{\"hostname\":\"$hostname\",\"ip\":\"$ip\",\"mac\":\"$mac\",\"method\":\"mdns\",\"verified\":true}" >> "$DISCOVERY_FILE.tmp"
            
            # Suggest updating static config
            echo -e "    ${YELLOW}Consider updating static IP to: $ip${NC}"
            return 0
        fi
    fi
    
    echo "    Not found via fallback methods"
    return 1
}

# Function to perform quick discovery
quick_discover() {
    echo -e "\n${YELLOW}Phase 1: Testing Known Static IPs${NC}"
    
    local found=0
    local missing=0
    
    # Check if static config exists
    if [ ! -f "$STATIC_CONFIG" ]; then
        echo -e "${RED}Error: $STATIC_CONFIG not found!${NC}"
        echo "Run: ./manage-static-dhcp.sh"
        exit 1
    fi
    
    # Test each static IP
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value.ip) \(.value.mac)"' "$STATIC_CONFIG" | \
    while IFS=' ' read -r hostname ip mac; do
        if test_static_ip "$hostname" "$ip" "$mac"; then
            found=$((found + 1))
        else
            missing=$((missing + 1))
        fi
    done
    
    echo ""
    echo "  Found: $found Pis at their static IPs"
    
    if [ $missing -gt 0 ]; then
        echo -e "\n${YELLOW}Phase 2: Searching for Missing Pis${NC}"
        
        jq -r '.static_leases | to_entries[] | "\(.key) \(.value.ip)"' "$STATIC_CONFIG" | \
        while IFS=' ' read -r hostname ip; do
            # Check if we already found this one
            if ! grep -q "\"hostname\":\"$hostname\"" "$DISCOVERY_FILE.tmp" 2>/dev/null; then
                discover_fallback "$hostname"
            fi
        done
    fi
}

# Function to generate Ansible inventory
generate_inventory() {
    echo -e "\n${YELLOW}Generating Ansible Inventory${NC}"
    
    # Read static config for roles
    cat > "${ANSIBLE_INVENTORY}.static" << EOF
---
# Auto-generated Ansible inventory (Static DHCP)
# Generated: $(date)

all:
  vars:
    ansible_user: pi
    ansible_ssh_private_key_file: ${SSH_KEY}
    ansible_python_interpreter: /usr/bin/python3
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
    
  children:
    pis:
      hosts:
EOF
    
    # Add each Pi with its static IP
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value)"' "$STATIC_CONFIG" | while IFS=' ' read -r hostname data; do
        ip=$(echo "$data" | jq -r '.ip')
        role=$(echo "$data" | jq -r '.role')
        mac=$(echo "$data" | jq -r '.mac')
        
        # Check if Pi is reachable
        verified="false"
        if grep -q "\"hostname\":\"$hostname\".*\"verified\":true" "$DISCOVERY_FILE" 2>/dev/null; then
            verified="true"
        fi
        
        cat >> "${ANSIBLE_INVENTORY}.static" << EOF
        $hostname:
          ansible_host: $ip
          static_ip: $ip
          mac_address: "$mac"
          role: $role
          online: $verified
EOF
    done
    
    # Add group vars
    cat >> "${ANSIBLE_INVENTORY}.static" << EOF
      
    monitoring:
      hosts:
        pi-a:
    
    ingress:
      hosts:
        pi-b:
    
    workers:
      hosts:
        pi-c:
    
    backup:
      hosts:
        pi-d:
EOF
    
    echo -e "${GREEN}✓ Ansible inventory saved to: ${ANSIBLE_INVENTORY}.static${NC}"
}

# Function to generate hosts file entries
generate_hosts() {
    echo -e "\n${YELLOW}Generating /etc/hosts entries${NC}"
    
    local hosts_file="hosts.static"
    
    echo "# Static DHCP entries for Pi cluster" > "$hosts_file"
    echo "# Add to /etc/hosts for reliable resolution" >> "$hosts_file"
    echo "" >> "$hosts_file"
    
    jq -r '.static_leases | to_entries[] | "\(.value.ip) \(.key) \(.key).local"' "$STATIC_CONFIG" >> "$hosts_file"
    
    echo -e "${GREEN}✓ Hosts entries saved to: $hosts_file${NC}"
    echo ""
    echo "To apply:"
    echo "  sudo cat $hosts_file >> /etc/hosts"
}

# Function to update SSH config
update_ssh_config() {
    echo -e "\n${YELLOW}Updating SSH config${NC}"
    
    cat > "$HOME/.ssh/config.d/pi-cluster-static" << EOF
# Static DHCP SSH configuration for Pi cluster
# Generated: $(date)

EOF
    
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value.ip)"' "$STATIC_CONFIG" | while IFS=' ' read -r hostname ip; do
        cat >> "$HOME/.ssh/config.d/pi-cluster-static" << EOF
Host $hostname
    HostName $ip
    User pi
    IdentityFile $SSH_KEY
    StrictHostKeyChecking no
    ServerAliveInterval 60
    ServerAliveCountMax 3

EOF
    done
    
    echo -e "${GREEN}✓ SSH config updated${NC}"
}

# Function to show summary
show_summary() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}   Discovery Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    if [ -f "$DISCOVERY_FILE" ]; then
        echo -e "${YELLOW}Static IPs (Configured):${NC}"
        jq -r '.static_leases | to_entries[] | "  \(.key): \(.value.ip)"' "$STATIC_CONFIG"
        
        echo -e "\n${YELLOW}Discovery Results:${NC}"
        jq -r 'group_by(.hostname) | .[] | .[0] | "  \(.hostname): \(.ip) [\(.method)] \(if .verified then "✓" else "✗" end)"' "$DISCOVERY_FILE"
        
        echo -e "\n${YELLOW}MAC Addresses:${NC}"
        jq -r 'select(.mac != "unknown" and .mac != null) | "  \(.hostname): \(.mac)"' "$DISCOVERY_FILE"
    else
        echo -e "${RED}No discovery results found${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Generated Files:${NC}"
    [ -f "${ANSIBLE_INVENTORY}.static" ] && echo "  • Ansible inventory: ${ANSIBLE_INVENTORY}.static"
    [ -f "hosts.static" ] && echo "  • Hosts file: hosts.static"
    [ -f "$HOME/.ssh/config.d/pi-cluster-static" ] && echo "  • SSH config: ~/.ssh/config.d/pi-cluster-static"
    [ -f "$DISCOVERY_FILE" ] && echo "  • Discovery results: $DISCOVERY_FILE"
}

# Main execution
main() {
    # Clean previous results
    rm -f "$DISCOVERY_FILE" "$DISCOVERY_FILE.tmp"
    
    # Check for required tools
    if ! command -v jq &>/dev/null; then
        echo -e "${YELLOW}Installing jq...${NC}"
        sudo apt-get update && sudo apt-get install -y jq
    fi
    
    # Run discovery
    quick_discover
    
    # Process results
    if [ -f "$DISCOVERY_FILE.tmp" ]; then
        # Convert to proper JSON array
        echo "[" > "$DISCOVERY_FILE"
        cat "$DISCOVERY_FILE.tmp" | paste -sd ',' >> "$DISCOVERY_FILE"
        echo "]" >> "$DISCOVERY_FILE"
        rm -f "$DISCOVERY_FILE.tmp"
        
        # Generate configurations
        generate_inventory
        generate_hosts
        update_ssh_config
        
        # Show summary
        show_summary
        
        echo -e "\n${GREEN}✓ Discovery complete!${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Review static IPs in: $STATIC_CONFIG"
        echo "2. Configure DHCP server: ./manage-static-dhcp.sh generate"
        echo "3. Test connectivity: ansible -i ${ANSIBLE_INVENTORY}.static pis -m ping"
    else
        echo -e "${RED}No Pis discovered!${NC}"
        echo ""
        echo "Troubleshooting:"
        echo "1. Check static IPs in: $STATIC_CONFIG"
        echo "2. Ensure Pis are powered on"
        echo "3. Verify network connectivity"
        echo "4. Run: ./manage-static-dhcp.sh verify"
    fi
}

# Run main
main "$@"