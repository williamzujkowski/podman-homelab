#!/bin/bash
# Raspberry Pi Discovery Script
# Finds all Pis on the network and updates Ansible inventory

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
ANSIBLE_INVENTORY="../ansible/inventories/prod/hosts.yml"
DISCOVERY_FILE="discovered-pis.json"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/pi_ed25519}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Raspberry Pi Network Discovery${NC}"
echo -e "${GREEN}========================================${NC}"

# Function to discover via mDNS
discover_mdns() {
    echo -e "\n${YELLOW}Method 1: Discovering via mDNS (.local)...${NC}"
    
    local found=0
    for hostname in pi-a pi-b pi-c pi-d; do
        echo -n "  Looking for ${hostname}.local..."
        
        # Try avahi-resolve
        if command -v avahi-resolve &>/dev/null; then
            ip=$(avahi-resolve -n "${hostname}.local" 2>/dev/null | awk '{print $2}')
        fi
        
        # Fallback to getent
        if [ -z "$ip" ]; then
            ip=$(getent hosts "${hostname}.local" 2>/dev/null | awk '{print $1}')
        fi
        
        # Fallback to ping
        if [ -z "$ip" ]; then
            ip=$(ping -c 1 -W 1 "${hostname}.local" 2>/dev/null | grep PING | sed -r 's/.*\(([0-9.]+)\).*/\1/' || true)
        fi
        
        if [ -n "$ip" ]; then
            echo -e " ${GREEN}✓ Found at $ip${NC}"
            echo "{\"hostname\":\"$hostname\",\"ip\":\"$ip\",\"method\":\"mdns\"}" >> "$DISCOVERY_FILE.tmp"
            found=$((found + 1))
        else
            echo -e " ${YELLOW}✗ Not found${NC}"
        fi
    done
    
    echo "  Found $found Pi(s) via mDNS"
    return $found
}

# Function to discover via ARP scan
discover_arp() {
    echo -e "\n${YELLOW}Method 2: Discovering via ARP scan...${NC}"
    
    # Get local network range
    local network=$(ip route | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.0' | head -1 | awk '{print $1}')
    
    if [ -z "$network" ]; then
        network="192.168.1.0/24"  # Default fallback
    fi
    
    echo "  Scanning network: $network"
    
    # Perform ARP scan
    if command -v arp-scan &>/dev/null; then
        # Use arp-scan if available
        sudo arp-scan "$network" 2>/dev/null | grep -i "raspberry\|b8:27:eb\|dc:a6:32\|e4:5f:01" | while read line; do
            ip=$(echo "$line" | awk '{print $1}')
            mac=$(echo "$line" | awk '{print $2}')
            echo "  Found Pi at $ip (MAC: $mac)"
            echo "{\"ip\":\"$ip\",\"mac\":\"$mac\",\"method\":\"arp\"}" >> "$DISCOVERY_FILE.tmp"
        done
    else
        # Fallback to nmap
        if command -v nmap &>/dev/null; then
            echo "  Using nmap for discovery..."
            nmap -sn "$network" 2>/dev/null | grep -B 2 -i "raspberry\|b8:27:eb\|dc:a6:32\|e4:5f:01" | grep "Nmap scan" | awk '{print $5}' | while read ip; do
                echo "  Found possible Pi at $ip"
                echo "{\"ip\":\"$ip\",\"method\":\"nmap\"}" >> "$DISCOVERY_FILE.tmp"
            done
        fi
    fi
}

# Function to discover via SSH probe
discover_ssh() {
    echo -e "\n${YELLOW}Method 3: Discovering via SSH probe...${NC}"
    
    local network=$(ip route | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.0' | head -1 | awk '{print $1}' | sed 's/\.0\/.*//')
    
    if [ -z "$network" ]; then
        network="192.168.1"  # Default
    fi
    
    echo "  Probing SSH on ${network}.0/24..."
    
    for i in {1..254}; do
        ip="${network}.${i}"
        
        # Quick SSH probe with timeout
        if timeout 0.5 bash -c "echo > /dev/tcp/$ip/22" 2>/dev/null; then
            # Try to get hostname via SSH
            hostname=$(timeout 2 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=1 -i "$SSH_KEY" "pi@$ip" "hostname" 2>/dev/null || echo "")
            
            if [[ "$hostname" == pi-* ]]; then
                echo -e "  ${GREEN}✓ Found $hostname at $ip${NC}"
                echo "{\"hostname\":\"$hostname\",\"ip\":\"$ip\",\"method\":\"ssh\"}" >> "$DISCOVERY_FILE.tmp"
            elif [ -n "$hostname" ]; then
                echo "  Found SSH at $ip (hostname: $hostname)"
            fi
        fi
    done &
    
    # Wait for background jobs
    wait
}

# Function to discover via DHCP leases
discover_dhcp() {
    echo -e "\n${YELLOW}Method 4: Checking DHCP leases...${NC}"
    
    # Common DHCP lease file locations
    local lease_files=(
        "/var/lib/dhcp/dhclient.leases"
        "/var/lib/dhclient/dhclient.leases"
        "/var/lib/NetworkManager/dhclient-*.lease"
        "/tmp/dhcp.leases"
    )
    
    # If running on router/DHCP server
    if [ -f "/var/lib/misc/dnsmasq.leases" ]; then
        echo "  Checking dnsmasq leases..."
        grep -E "pi-[a-d]" /var/lib/misc/dnsmasq.leases | while read line; do
            ip=$(echo "$line" | awk '{print $3}')
            hostname=$(echo "$line" | awk '{print $4}')
            echo "  Found $hostname at $ip"
            echo "{\"hostname\":\"$hostname\",\"ip\":\"$ip\",\"method\":\"dhcp\"}" >> "$DISCOVERY_FILE.tmp"
        done
    fi
    
    # Check ISC DHCP server leases
    if [ -f "/var/lib/dhcp/dhcpd.leases" ]; then
        echo "  Checking ISC DHCP leases..."
        awk '/^lease/ {ip=$2} /client-hostname/ {print ip, $2}' /var/lib/dhcp/dhcpd.leases | grep -E "pi-[a-d]" | while read ip hostname; do
            hostname=$(echo "$hostname" | tr -d '";')
            echo "  Found $hostname at $ip"
            echo "{\"hostname\":\"$hostname\",\"ip\":\"$ip\",\"method\":\"dhcp\"}" >> "$DISCOVERY_FILE.tmp"
        done
    fi
}

# Function to verify discovered Pis
verify_pi() {
    local ip="$1"
    local hostname="$2"
    
    echo -n "  Verifying $hostname at $ip..."
    
    # Try SSH with key
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 -i "$SSH_KEY" "pi@$ip" "hostname" &>/dev/null; then
        echo -e " ${GREEN}✓ SSH OK${NC}"
        return 0
    else
        echo -e " ${YELLOW}⚠ SSH failed${NC}"
        return 1
    fi
}

# Function to update Ansible inventory
update_inventory() {
    echo -e "\n${YELLOW}Updating Ansible inventory...${NC}"
    
    if [ ! -f "$DISCOVERY_FILE" ]; then
        echo -e "${RED}No Pis discovered!${NC}"
        return 1
    fi
    
    # Parse discovered Pis
    local pi_a_ip=$(jq -r 'select(.hostname=="pi-a") | .ip' "$DISCOVERY_FILE" | head -1)
    local pi_b_ip=$(jq -r 'select(.hostname=="pi-b") | .ip' "$DISCOVERY_FILE" | head -1)
    local pi_c_ip=$(jq -r 'select(.hostname=="pi-c") | .ip' "$DISCOVERY_FILE" | head -1)
    local pi_d_ip=$(jq -r 'select(.hostname=="pi-d") | .ip' "$DISCOVERY_FILE" | head -1)
    
    # Create dynamic inventory
    cat > "${ANSIBLE_INVENTORY}.dynamic" << EOF
---
# Auto-generated inventory from discovery
# Generated: $(date)

all:
  children:
    pis:
      hosts:
        pi-a:
          ansible_host: "${pi_a_ip:-UNKNOWN}"
          ansible_user: pi
          ansible_ssh_private_key_file: ${SSH_KEY}
          role: monitoring
        pi-b:
          ansible_host: "${pi_b_ip:-UNKNOWN}"
          ansible_user: pi
          ansible_ssh_private_key_file: ${SSH_KEY}
          role: ingress
        pi-c:
          ansible_host: "${pi_c_ip:-UNKNOWN}"
          ansible_user: pi
          ansible_ssh_private_key_file: ${SSH_KEY}
          role: worker
        pi-d:
          ansible_host: "${pi_d_ip:-UNKNOWN}"
          ansible_user: pi
          ansible_ssh_private_key_file: ${SSH_KEY}
          role: backup
      vars:
        ansible_python_interpreter: /usr/bin/python3
        ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
EOF
    
    echo -e "${GREEN}✓ Inventory updated at ${ANSIBLE_INVENTORY}.dynamic${NC}"
}

# Function to generate SSH config
generate_ssh_config() {
    echo -e "\n${YELLOW}Generating SSH config...${NC}"
    
    if [ ! -f "$DISCOVERY_FILE" ]; then
        return 1
    fi
    
    cat > "$HOME/.ssh/config.d/pi-cluster" << EOF
# Auto-generated SSH config for Pi cluster
# Generated: $(date)

EOF
    
    jq -r '.hostname + " " + .ip' "$DISCOVERY_FILE" 2>/dev/null | while read hostname ip; do
        if [ -n "$hostname" ] && [ -n "$ip" ]; then
            cat >> "$HOME/.ssh/config.d/pi-cluster" << EOF
Host $hostname
    HostName $ip
    User pi
    IdentityFile $SSH_KEY
    StrictHostKeyChecking no
    ServerAliveInterval 60
    ServerAliveCountMax 3

EOF
        fi
    done
    
    echo -e "${GREEN}✓ SSH config written to ~/.ssh/config.d/pi-cluster${NC}"
    
    # Include in main SSH config if not already
    if ! grep -q "Include ~/.ssh/config.d/\*" ~/.ssh/config 2>/dev/null; then
        echo "Include ~/.ssh/config.d/*" >> ~/.ssh/config
        echo -e "${GREEN}✓ Added include to main SSH config${NC}"
    fi
}

# Main discovery process
main() {
    # Clean up previous discovery
    rm -f "$DISCOVERY_FILE" "$DISCOVERY_FILE.tmp"
    
    # Check for required tools
    echo -e "${YELLOW}Checking required tools...${NC}"
    local tools_needed=""
    
    for tool in jq nc; do
        if ! command -v $tool &>/dev/null; then
            tools_needed="$tools_needed $tool"
        fi
    done
    
    if [ -n "$tools_needed" ]; then
        echo -e "${YELLOW}Installing required tools:$tools_needed${NC}"
        sudo apt-get update && sudo apt-get install -y $tools_needed
    fi
    
    # Run discovery methods
    discover_mdns || true
    discover_arp || true
    discover_ssh || true
    discover_dhcp || true
    
    # Deduplicate results
    if [ -f "$DISCOVERY_FILE.tmp" ]; then
        sort -u "$DISCOVERY_FILE.tmp" | jq -s '.' > "$DISCOVERY_FILE"
        rm -f "$DISCOVERY_FILE.tmp"
    fi
    
    # Show results
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}   Discovery Results${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    if [ -f "$DISCOVERY_FILE" ]; then
        echo ""
        jq -r '"  " + .hostname + " (" + .role + "): " + .ip + " [" + .method + "]"' "$DISCOVERY_FILE" 2>/dev/null | sort -u
        
        # Verify each Pi
        echo -e "\n${YELLOW}Verifying SSH access...${NC}"
        jq -r '.hostname + " " + .ip' "$DISCOVERY_FILE" 2>/dev/null | sort -u | while read hostname ip; do
            if [ -n "$hostname" ] && [ -n "$ip" ]; then
                verify_pi "$ip" "$hostname" || true
            fi
        done
        
        # Update configurations
        update_inventory
        generate_ssh_config
        
        echo -e "\n${GREEN}Discovery complete!${NC}"
        echo "  Results saved to: $DISCOVERY_FILE"
        echo "  Ansible inventory: ${ANSIBLE_INVENTORY}.dynamic"
        echo "  SSH config: ~/.ssh/config.d/pi-cluster"
        echo ""
        echo "Test connection:"
        echo "  ssh pi-a"
        echo "  ssh pi-b"
        echo "  ansible -i ${ANSIBLE_INVENTORY}.dynamic pis -m ping"
    else
        echo -e "${RED}No Pis found on network!${NC}"
        echo ""
        echo "Troubleshooting:"
        echo "1. Ensure Pis are powered on and connected to network"
        echo "2. Wait 5-10 minutes for boot to complete"
        echo "3. Check your network's DHCP server"
        echo "4. Try: ping pi-a.local"
    fi
}

# Run main function
main "$@"