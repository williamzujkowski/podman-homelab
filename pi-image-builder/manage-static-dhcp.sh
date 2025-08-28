#!/bin/bash
# Static DHCP Management Script
# Manages MAC addresses and generates DHCP server configurations

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration files
CONFIG_FILE="static-dhcp-config.json"
MAC_INVENTORY="mac-addresses.txt"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/pi_ed25519}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Static DHCP Configuration Manager${NC}"
echo -e "${BLUE}========================================${NC}"

# Function to display current configuration
show_config() {
    echo -e "\n${YELLOW}Current Static DHCP Configuration:${NC}"
    echo ""
    jq -r '.static_leases | to_entries[] | "  \(.key): \(.value.ip) (MAC: \(.value.mac))"' "$CONFIG_FILE"
    echo ""
    echo -e "${YELLOW}Network Settings:${NC}"
    jq -r '.network | "  Subnet: \(.subnet)\n  Gateway: \(.gateway)\n  DNS: \(.dns_primary), \(.dns_secondary)"' "$CONFIG_FILE"
}

# Function to collect MAC addresses from live Pis
collect_macs() {
    echo -e "\n${YELLOW}Collecting MAC addresses from Pis...${NC}"
    
    # Read current config
    local temp_config=$(mktemp)
    cp "$CONFIG_FILE" "$temp_config"
    
    # Try to get MAC for each configured Pi
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value.ip)"' "$CONFIG_FILE" | while read hostname ip; do
        echo -n "  Checking $hostname ($ip)..."
        
        # Try multiple methods to get MAC
        local mac=""
        
        # Method 1: SSH and get MAC
        if [ -n "$ip" ] && [ "$ip" != "null" ]; then
            mac=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -i "$SSH_KEY" "pi@$ip" \
                "ip link show eth0 2>/dev/null | grep 'link/ether' | awk '{print \$2}'" 2>/dev/null || true)
        fi
        
        # Method 2: Try via hostname if IP failed
        if [ -z "$mac" ]; then
            mac=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -i "$SSH_KEY" "pi@${hostname}.local" \
                "ip link show eth0 2>/dev/null | grep 'link/ether' | awk '{print \$2}'" 2>/dev/null || true)
        fi
        
        # Method 3: ARP cache
        if [ -z "$mac" ] && [ "$ip" != "null" ]; then
            mac=$(arp -n "$ip" 2>/dev/null | grep -v "incomplete" | awk '{print $3}' | grep -E "^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$" || true)
        fi
        
        if [ -n "$mac" ]; then
            echo -e " ${GREEN}✓ MAC: $mac${NC}"
            # Update config file
            jq ".static_leases.\"$hostname\".mac = \"$mac\"" "$temp_config" > "${temp_config}.new"
            mv "${temp_config}.new" "$temp_config"
            # Save to inventory
            echo "$hostname $ip $mac" >> "$MAC_INVENTORY"
        else
            echo -e " ${YELLOW}✗ Could not retrieve MAC${NC}"
        fi
    done
    
    # Update main config
    mv "$temp_config" "$CONFIG_FILE"
    echo -e "${GREEN}✓ MAC addresses updated in $CONFIG_FILE${NC}"
    
    # Remove duplicates from inventory
    if [ -f "$MAC_INVENTORY" ]; then
        sort -u "$MAC_INVENTORY" > "${MAC_INVENTORY}.tmp"
        mv "${MAC_INVENTORY}.tmp" "$MAC_INVENTORY"
    fi
}

# Function to generate ISC DHCP server config
generate_isc_dhcp() {
    echo -e "\n${YELLOW}Generating ISC DHCP Server configuration...${NC}"
    
    local output_file="dhcpd.conf.generated"
    
    cat > "$output_file" << 'EOF'
# ISC DHCP Server Configuration
# Generated for Pi Cluster Static Leases

# Global options
option domain-name "local";
option domain-name-servers 192.168.1.1, 1.1.1.1;

default-lease-time 86400;
max-lease-time 172800;

# Use this to enable / disable dynamic dns updates
ddns-update-style none;

# Authoritative for this network
authoritative;

EOF
    
    # Add subnet configuration
    local subnet=$(jq -r '.network.subnet' "$CONFIG_FILE")
    local gateway=$(jq -r '.network.gateway' "$CONFIG_FILE")
    local pool_start=$(jq -r '.dhcp_pool.start' "$CONFIG_FILE")
    local pool_end=$(jq -r '.dhcp_pool.end' "$CONFIG_FILE")
    
    cat >> "$output_file" << EOF
# Network subnet
subnet ${subnet%/*} netmask 255.255.255.0 {
    range $pool_start $pool_end;
    option routers $gateway;
    option broadcast-address ${subnet%.*}.255;
    
    # Static leases for Raspberry Pis
EOF
    
    # Add static leases
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value)"' "$CONFIG_FILE" | while IFS=' ' read -r hostname data; do
        ip=$(echo "$data" | jq -r '.ip')
        mac=$(echo "$data" | jq -r '.mac')
        
        if [ "$mac" != "PENDING" ] && [ "$mac" != "null" ]; then
            cat >> "$output_file" << EOF
    
    host $hostname {
        hardware ethernet $mac;
        fixed-address $ip;
        option host-name "$hostname";
    }
EOF
        fi
    done
    
    echo "}" >> "$output_file"
    
    echo -e "${GREEN}✓ ISC DHCP config saved to: $output_file${NC}"
}

# Function to generate dnsmasq config
generate_dnsmasq() {
    echo -e "\n${YELLOW}Generating dnsmasq configuration...${NC}"
    
    local output_file="dnsmasq-dhcp.conf.generated"
    
    cat > "$output_file" << 'EOF'
# dnsmasq DHCP Configuration
# Generated for Pi Cluster Static Leases

# DHCP range and lease time
EOF
    
    local pool_start=$(jq -r '.dhcp_pool.start' "$CONFIG_FILE")
    local pool_end=$(jq -r '.dhcp_pool.end' "$CONFIG_FILE")
    local lease_time=$(jq -r '.dhcp_pool.lease_time' "$CONFIG_FILE")
    
    echo "dhcp-range=$pool_start,$pool_end,${lease_time}s" >> "$output_file"
    
    cat >> "$output_file" << 'EOF'

# Gateway
dhcp-option=3,192.168.1.1

# DNS servers
dhcp-option=6,192.168.1.1,1.1.1.1

# Domain
domain=local

# Static leases for Raspberry Pis
EOF
    
    # Add static leases
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value)"' "$CONFIG_FILE" | while IFS=' ' read -r hostname data; do
        ip=$(echo "$data" | jq -r '.ip')
        mac=$(echo "$data" | jq -r '.mac')
        
        if [ "$mac" != "PENDING" ] && [ "$mac" != "null" ]; then
            echo "dhcp-host=$mac,$ip,$hostname,infinite" >> "$output_file"
        fi
    done
    
    echo -e "${GREEN}✓ dnsmasq config saved to: $output_file${NC}"
}

# Function to generate OpenWrt/LuCI config
generate_openwrt() {
    echo -e "\n${YELLOW}Generating OpenWrt UCI configuration...${NC}"
    
    local output_file="openwrt-dhcp.sh.generated"
    
    cat > "$output_file" << 'EOF'
#!/bin/sh
# OpenWrt UCI Commands for Static DHCP Leases
# Run on OpenWrt router via SSH

echo "Configuring static DHCP leases for Pi cluster..."

EOF
    
    # Add static leases
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value)"' "$CONFIG_FILE" | while IFS=' ' read -r hostname data; do
        ip=$(echo "$data" | jq -r '.ip')
        mac=$(echo "$data" | jq -r '.mac')
        
        if [ "$mac" != "PENDING" ] && [ "$mac" != "null" ]; then
            cat >> "$output_file" << EOF
# $hostname
uci add dhcp host
uci set dhcp.@host[-1].name='$hostname'
uci set dhcp.@host[-1].mac='$mac'
uci set dhcp.@host[-1].ip='$ip'

EOF
        fi
    done
    
    cat >> "$output_file" << 'EOF'
# Commit changes
uci commit dhcp
/etc/init.d/dnsmasq restart

echo "Static DHCP leases configured!"
EOF
    
    chmod +x "$output_file"
    echo -e "${GREEN}✓ OpenWrt config script saved to: $output_file${NC}"
}

# Function to generate pfSense config
generate_pfsense() {
    echo -e "\n${YELLOW}Generating pfSense configuration guide...${NC}"
    
    local output_file="pfsense-static-dhcp.md"
    
    cat > "$output_file" << 'EOF'
# pfSense Static DHCP Configuration

## Via Web Interface

1. Navigate to **Services > DHCP Server**
2. Select your LAN interface
3. Scroll down to **DHCP Static Mappings**
4. Click **+ Add** for each Pi:

EOF
    
    # Add entries for each Pi
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value)"' "$CONFIG_FILE" | while IFS=' ' read -r hostname data; do
        ip=$(echo "$data" | jq -r '.ip')
        mac=$(echo "$data" | jq -r '.mac')
        role=$(echo "$data" | jq -r '.role')
        
        if [ "$mac" != "PENDING" ] && [ "$mac" != "null" ]; then
            cat >> "$output_file" << EOF
### $hostname ($role)
- **MAC Address**: `$mac`
- **IP Address**: `$ip`
- **Hostname**: `$hostname`
- **Description**: `Raspberry Pi - $role node`

EOF
        fi
    done
    
    cat >> "$output_file" << 'EOF'
5. Click **Save** after each entry
6. Click **Apply Changes** when all entries are added

## Via Shell Commands

```bash
# SSH into pfSense and run:
EOF
    
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value)"' "$CONFIG_FILE" | while IFS=' ' read -r hostname data; do
        ip=$(echo "$data" | jq -r '.ip')
        mac=$(echo "$data" | jq -r '.mac')
        
        if [ "$mac" != "PENDING" ] && [ "$mac" != "null" ]; then
            echo "# $hostname" >> "$output_file"
            echo "echo '<staticmap><mac>$mac</mac><ipaddr>$ip</ipaddr><hostname>$hostname</hostname></staticmap>' >> /cf/conf/config.xml" >> "$output_file"
        fi
    done
    
    echo '```' >> "$output_file"
    
    echo -e "${GREEN}✓ pfSense guide saved to: $output_file${NC}"
}

# Function to update network configuration
update_network() {
    echo -e "\n${YELLOW}Update Network Configuration${NC}"
    echo ""
    
    read -p "Enter subnet (e.g., 192.168.1.0/24): " subnet
    read -p "Enter gateway IP: " gateway
    read -p "Enter primary DNS: " dns1
    read -p "Enter secondary DNS: " dns2
    read -p "Enter domain name: " domain
    
    # Update config
    jq ".network.subnet = \"$subnet\" | 
        .network.gateway = \"$gateway\" | 
        .network.dns_primary = \"$dns1\" | 
        .network.dns_secondary = \"$dns2\" | 
        .network.domain = \"$domain\"" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
    
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo -e "${GREEN}✓ Network configuration updated${NC}"
}

# Function to update Pi IP assignments
update_ips() {
    echo -e "\n${YELLOW}Update Static IP Assignments${NC}"
    echo ""
    
    for hostname in pi-a pi-b pi-c pi-d; do
        current_ip=$(jq -r ".static_leases.\"$hostname\".ip" "$CONFIG_FILE")
        read -p "IP for $hostname (current: $current_ip): " new_ip
        
        if [ -n "$new_ip" ]; then
            jq ".static_leases.\"$hostname\".ip = \"$new_ip\"" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
            mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        fi
    done
    
    echo -e "${GREEN}✓ IP assignments updated${NC}"
}

# Function to verify static leases are working
verify_leases() {
    echo -e "\n${YELLOW}Verifying Static DHCP Leases...${NC}"
    echo ""
    
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value.ip)"' "$CONFIG_FILE" | while read hostname ip; do
        echo -n "  Testing $hostname at $ip..."
        
        if ping -c 1 -W 2 "$ip" &>/dev/null; then
            # Verify hostname matches
            actual_hostname=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -i "$SSH_KEY" \
                "pi@$ip" "hostname" 2>/dev/null || echo "unknown")
            
            if [ "$actual_hostname" = "$hostname" ]; then
                echo -e " ${GREEN}✓ OK${NC}"
            else
                echo -e " ${YELLOW}⚠ Hostname mismatch (got: $actual_hostname)${NC}"
            fi
        else
            echo -e " ${RED}✗ Not responding${NC}"
        fi
    done
}

# Main menu
main_menu() {
    while true; do
        echo -e "\n${BLUE}========================================${NC}"
        echo -e "${BLUE}   Static DHCP Management Menu${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        echo "1) Show current configuration"
        echo "2) Collect MAC addresses from Pis"
        echo "3) Update network settings"
        echo "4) Update Pi IP assignments"
        echo "5) Generate ISC DHCP config"
        echo "6) Generate dnsmasq config"
        echo "7) Generate OpenWrt config"
        echo "8) Generate pfSense guide"
        echo "9) Generate ALL configs"
        echo "V) Verify static leases"
        echo "Q) Quit"
        echo ""
        read -p "Select option: " choice
        
        case $choice in
            1) show_config ;;
            2) collect_macs ;;
            3) update_network ;;
            4) update_ips ;;
            5) generate_isc_dhcp ;;
            6) generate_dnsmasq ;;
            7) generate_openwrt ;;
            8) generate_pfsense ;;
            9) 
                generate_isc_dhcp
                generate_dnsmasq
                generate_openwrt
                generate_pfsense
                ;;
            v|V) verify_leases ;;
            q|Q) 
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac
    done
}

# Parse command line arguments
case "${1:-}" in
    collect)
        collect_macs
        ;;
    generate)
        generate_isc_dhcp
        generate_dnsmasq
        generate_openwrt
        generate_pfsense
        ;;
    verify)
        verify_leases
        ;;
    show)
        show_config
        ;;
    *)
        main_menu
        ;;
esac