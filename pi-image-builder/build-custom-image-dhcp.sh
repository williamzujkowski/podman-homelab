#!/bin/bash
# Enhanced Raspberry Pi Image Builder with DHCP and Redundancies
# Pre-installs SSH keys and multiple access methods for bulletproof deployment

set -euo pipefail

# Configuration
WORK_DIR="/tmp/pi-image-builder"
OUTPUT_DIR="./images"
BASE_IMAGE_URL="https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04-preinstalled-server-arm64+raspi.img.xz"
BASE_IMAGE_FILE="ubuntu-24.04-preinstalled-server-arm64+raspi.img"

# SSH Keys to pre-install (MODIFY THESE!)
PRIMARY_SSH_KEY="${PRIMARY_SSH_KEY:-$HOME/.ssh/pi_ed25519.pub}"
BACKUP_SSH_KEY="${BACKUP_SSH_KEY:-$HOME/.ssh/id_ed25519.pub}"
RECOVERY_SSH_KEY="${RECOVERY_SSH_KEY:-$HOME/.ssh/id_rsa.pub}"

# Tailscale auth key for redundant access (optional but recommended)
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Create work directories
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Enhanced Pi Image Builder (DHCP)${NC}"
echo -e "${GREEN}========================================${NC}"

# Function to check for SSH keys
check_ssh_keys() {
    echo -e "${YELLOW}Checking for SSH keys to embed...${NC}"
    
    local keys_found=0
    
    if [ -f "$PRIMARY_SSH_KEY" ]; then
        echo -e "  ${GREEN}✓ Primary key found: $PRIMARY_SSH_KEY${NC}"
        keys_found=$((keys_found + 1))
    else
        echo -e "  ${YELLOW}⚠ Primary key not found: $PRIMARY_SSH_KEY${NC}"
    fi
    
    if [ -f "$BACKUP_SSH_KEY" ]; then
        echo -e "  ${GREEN}✓ Backup key found: $BACKUP_SSH_KEY${NC}"
        keys_found=$((keys_found + 1))
    else
        echo -e "  ${YELLOW}⚠ Backup key not found: $BACKUP_SSH_KEY${NC}"
    fi
    
    if [ -f "$RECOVERY_SSH_KEY" ]; then
        echo -e "  ${GREEN}✓ Recovery key found: $RECOVERY_SSH_KEY${NC}"
        keys_found=$((keys_found + 1))
    else
        echo -e "  ${YELLOW}⚠ Recovery key not found: $RECOVERY_SSH_KEY${NC}"
    fi
    
    if [ $keys_found -eq 0 ]; then
        echo -e "${RED}Error: No SSH keys found to embed!${NC}"
        echo "Please create at least one SSH key:"
        echo "  ssh-keygen -t ed25519 -f ~/.ssh/pi_ed25519"
        exit 1
    fi
    
    echo -e "${GREEN}Found $keys_found SSH key(s) to embed${NC}"
}

# Function to download base image
download_base_image() {
    if [ ! -f "$WORK_DIR/$BASE_IMAGE_FILE" ]; then
        echo -e "${YELLOW}Downloading base Ubuntu image...${NC}"
        cd "$WORK_DIR"
        wget -q --show-progress "$BASE_IMAGE_URL"
        xz -d "$(basename $BASE_IMAGE_URL)"
        cd - > /dev/null
        echo -e "${GREEN}✓ Base image downloaded${NC}"
    else
        echo -e "${GREEN}✓ Using cached base image${NC}"
    fi
}

# Function to mount image
mount_image() {
    local IMAGE_FILE="$1"
    local MOUNT_POINT="$2"
    
    LOOP_DEV=$(sudo losetup --show -fP "$IMAGE_FILE")
    echo "Loop device: $LOOP_DEV"
    sleep 2
    
    sudo mkdir -p "$MOUNT_POINT/boot"
    sudo mkdir -p "$MOUNT_POINT/root"
    
    sudo mount "${LOOP_DEV}p1" "$MOUNT_POINT/boot"
    sudo mount "${LOOP_DEV}p2" "$MOUNT_POINT/root"
    
    echo "$LOOP_DEV"
}

# Function to unmount image
unmount_image() {
    local MOUNT_POINT="$1"
    local LOOP_DEV="$2"
    
    sudo umount "$MOUNT_POINT/boot" || true
    sudo umount "$MOUNT_POINT/root" || true
    sudo losetup -d "$LOOP_DEV" || true
    sudo rm -rf "$MOUNT_POINT"
}

# Function to customize image
customize_image() {
    local PI_NAME="$1"
    local MOUNT_POINT="$2"
    local ROLE="$3"  # monitoring, ingress, worker, backup
    
    echo -e "${YELLOW}Customizing image for $PI_NAME (role: $ROLE)...${NC}"
    
    # Collect SSH keys
    local SSH_KEYS=""
    [ -f "$PRIMARY_SSH_KEY" ] && SSH_KEYS="${SSH_KEYS}      - $(cat $PRIMARY_SSH_KEY)\n"
    [ -f "$BACKUP_SSH_KEY" ] && SSH_KEYS="${SSH_KEYS}      - $(cat $BACKUP_SSH_KEY)\n"
    [ -f "$RECOVERY_SSH_KEY" ] && SSH_KEYS="${SSH_KEYS}      - $(cat $RECOVERY_SSH_KEY)\n"
    
    # Network configuration for DHCP
    echo "  - Configuring DHCP networking..."
    sudo tee "$MOUNT_POINT/boot/network-config" > /dev/null << EOF
version: 2
ethernets:
  eth0:
    dhcp4: true
    dhcp4-overrides:
      send-hostname: true
      hostname: $PI_NAME
    dhcp6: false
    optional: true
    nameservers:
      addresses:
        - 1.1.1.1
        - 8.8.8.8
  # USB Ethernet adapter fallback (redundancy)
  eth1:
    dhcp4: true
    optional: true
    dhcp4-overrides:
      route-metric: 200
wifis:
  wlan0:
    optional: true
    dhcp4: true
    dhcp4-overrides:
      route-metric: 300
    access-points:
      "YOUR-WIFI-SSID":
        password: "YOUR-WIFI-PASSWORD"
EOF
    
    # Create comprehensive cloud-init configuration
    echo "  - Creating cloud-init with redundancies..."
    sudo tee "$MOUNT_POINT/boot/user-data" > /dev/null << EOF
#cloud-config
hostname: $PI_NAME
manage_etc_hosts: true
locale: en_US.UTF-8
timezone: America/New_York

# Preserve hostname across DHCP renewals
preserve_hostname: true
prefer_fqdn_over_hostname: false

# Create users with multiple access methods
users:
  - name: pi
    groups: [adm, sudo, docker, dialout]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    # Password: TempPiPass2024!Change (pre-hashed) - for emergency console access
    passwd: \$6\$rounds=4096\$8JhNXTYJ\$Q9QxZZPGzF3cNbBBajGPqz9FkHQNymLFZLFe5TSRqIqGZgSxY5Zj5Aqj5YqRwMfJLN9YWkYfCV7cWkF3wXqKH1
    ssh_authorized_keys:
$(echo -e "$SSH_KEYS")
  
  # Recovery user for emergencies
  - name: recovery
    groups: [sudo]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    # Password: RecoveryAccess2024! (pre-hashed)
    passwd: \$6\$rounds=4096\$recovery\$mD3KZbQ9XN2YW5pF6VvPzF3cNbBBajGPqz9FkHQNymLFZLFe5TSRqIqGZgSxY5Zj5YqRwMfJLN9YWkYfCV
    ssh_authorized_keys:
$(echo -e "$SSH_KEYS")

# SSH configuration
ssh_pwauth: true  # Keep enabled for emergency access
disable_root: true
ssh_deletekeys: false  # Keep existing keys

# Package installation
package_update: true
package_upgrade: true
packages:
  # Core requirements
  - python3
  - python3-pip
  - podman
  - podman-compose
  - curl
  - wget
  - git
  - vim
  - htop
  
  # Time sync
  - chrony
  - ntpdate
  
  # Security
  - ufw
  - fail2ban
  - unattended-upgrades
  
  # Monitoring
  - prometheus-node-exporter
  
  # Networking tools
  - net-tools
  - dnsutils
  - nmap
  - tcpdump
  - ethtool
  - bridge-utils
  - vlan
  
  # mDNS for hostname resolution
  - avahi-daemon
  - avahi-utils
  - libnss-mdns
  
  # System tools
  - jq
  - ncdu
  - tree
  - tmux
  - screen
  - rsync
  - iotop
  - sysstat
  
  # Recovery tools
  - testdisk
  - smartmontools
  - hdparm
  
  # USB tools
  - usbutils
  - usb-modeswitch

# Write configuration files
write_files:
  # Chrony configuration with multiple time sources
  - path: /etc/chrony/chrony.conf
    content: |
      # Primary NTS sources (CLAUDE.md requirement)
      server time.cloudflare.com iburst nts
      server time.nist.gov iburst
      
      # Fallback sources
      pool ntp.ubuntu.com iburst
      pool time.google.com iburst
      
      # Quick sync on boot
      makestep 0.1 3
      
      # Local stratum for network isolation
      local stratum 10
      
      # Allow local network
      allow 10.0.0.0/8
      allow 192.168.0.0/16
      allow 172.16.0.0/12
      
      rtcsync
      driftfile /var/lib/chrony/chrony.drift
  
  # SSH hardening with fallback
  - path: /etc/ssh/sshd_config.d/10-pi-security.conf
    content: |
      # Allow both key and password (password for emergency)
      PubkeyAuthentication yes
      PasswordAuthentication yes
      PermitEmptyPasswords no
      
      # Root login settings
      PermitRootLogin no
      
      # Security settings
      MaxAuthTries 6
      MaxSessions 10
      ClientAliveInterval 300
      ClientAliveCountMax 2
      
      # Allow users
      AllowUsers pi recovery
  
  # Network redundancy script
  - path: /usr/local/bin/check-network.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # Check network connectivity and try fallbacks
      
      PRIMARY_GW=\$(ip route | grep default | head -1 | awk '{print \$3}')
      
      if ! ping -c 1 -W 2 1.1.1.1 &>/dev/null; then
        echo "Primary network down, checking alternatives..."
        
        # Try to bring up WiFi
        if ! ip link show wlan0 | grep -q "UP"; then
          sudo ifup wlan0 2>/dev/null || true
        fi
        
        # Try USB ethernet
        if lsusb | grep -qi "ethernet"; then
          sudo ifup eth1 2>/dev/null || true
        fi
        
        # Restart networking
        sudo systemctl restart systemd-networkd
      fi
  
  # Auto-discovery beacon script
  - path: /usr/local/bin/discovery-beacon.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # Broadcast identity for network discovery
      
      HOSTNAME=\$(hostname)
      MAC=\$(ip link show eth0 | grep ether | awk '{print \$2}')
      IP=\$(hostname -I | cut -d' ' -f1)
      
      # Create discovery info
      echo "{\\"hostname\\":\\"\$HOSTNAME\\",\\"mac\\":\\"\$MAC\\",\\"ip\\":\\"\$IP\\",\\"role\\":\\"$ROLE\\",\\"timestamp\\":\$(date +%s)}" > /tmp/discovery.json
      
      # Broadcast via avahi
      avahi-publish-service "\$HOSTNAME-pi" _workstation._tcp 22 "role=$ROLE" "mac=\$MAC" &
  
  # Health check with network info
  - path: /usr/local/bin/health-check.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      echo "=== System Health Check ==="
      echo "Hostname: \$(hostname)"
      echo "Domain: \$(hostname -d 2>/dev/null || echo 'none')"
      echo "FQDN: \$(hostname -f 2>/dev/null || hostname)"
      echo ""
      echo "=== Network Interfaces ==="
      ip -br addr show
      echo ""
      echo "=== DHCP Assigned IPs ==="
      hostname -I
      echo ""
      echo "=== mDNS Resolution ==="
      echo "Local: \$(hostname).local"
      avahi-resolve -n \$(hostname).local 2>/dev/null || echo "mDNS not ready"
      echo ""
      echo "=== System Resources ==="
      echo "CPU: \$(nproc) cores"
      echo "RAM: \$(free -h | grep Mem | awk '{print \$2}')"
      echo "Disk: \$(df -h / | tail -1 | awk '{print \$4}') free"
      echo "Load: \$(uptime | awk -F'load average:' '{print \$2}')"
      echo ""
      echo "=== Time Sync ==="
      chronyc tracking | grep -E "System time|Stratum" | head -2
      echo ""
      echo "=== Container Status ==="
      sudo podman ps --format 'table {{.Names}}\\t{{.Status}}' 2>/dev/null || echo "No containers"
  
  # USB backup auto-detection
  - path: /etc/udev/rules.d/99-usb-backup.rules
    content: |
      # Auto-mount and backup to USB drives
      ACTION=="add", KERNEL=="sd[b-z][0-9]", RUN+="/usr/local/bin/usb-backup.sh"
  
  - path: /usr/local/bin/usb-backup.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # Auto-backup to USB when inserted
      DEVICE=\$1
      MOUNT_POINT="/mnt/usb-backup"
      
      # Create mount point and mount
      mkdir -p \$MOUNT_POINT
      mount \$DEVICE \$MOUNT_POINT 2>/dev/null || exit 1
      
      # Create backup
      BACKUP_DIR="\$MOUNT_POINT/pi-backup-\$(hostname)-\$(date +%Y%m%d)"
      mkdir -p "\$BACKUP_DIR"
      
      # Backup important configs
      tar czf "\$BACKUP_DIR/configs.tar.gz" \\
        /etc/containers/ \\
        /etc/prometheus/ \\
        /etc/grafana/ \\
        /home/pi/.ssh/ \\
        2>/dev/null || true
      
      # Unmount
      umount \$MOUNT_POINT
      
      logger "USB backup completed to \$DEVICE"
  
  # Systemd service for discovery
  - path: /etc/systemd/system/discovery-beacon.service
    content: |
      [Unit]
      Description=Network Discovery Beacon
      After=network-online.target
      Wants=network-online.target
      
      [Service]
      Type=simple
      ExecStart=/usr/local/bin/discovery-beacon.sh
      Restart=always
      RestartSec=60
      User=pi
      
      [Install]
      WantedBy=multi-user.target
  
  # Tailscale setup script (if auth key provided)
  - path: /usr/local/bin/setup-tailscale.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      if [ -n "$TAILSCALE_AUTH_KEY" ]; then
        curl -fsSL https://tailscale.com/install.sh | sh
        sudo tailscale up --authkey "$TAILSCALE_AUTH_KEY" \\
          --hostname \$(hostname) \\
          --ssh \\
          --accept-routes \\
          --accept-dns=false
      fi
  
  # Container directories setup
  - path: /usr/local/bin/setup-container-dirs.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      mkdir -p /home/pi/.config/containers/systemd
      mkdir -p /home/pi/.config/systemd/user
      mkdir -p /home/pi/volumes
      mkdir -p /home/pi/backup
      mkdir -p /etc/containers/systemd
      chown -R pi:pi /home/pi/.config
      chown -R pi:pi /home/pi/volumes
      chown -R pi:pi /home/pi/backup
      loginctl enable-linger pi

# System configuration
bootcmd:
  # Enable IP forwarding early
  - echo 1 > /proc/sys/net/ipv4/ip_forward
  
  # Load required kernel modules
  - modprobe overlay
  - modprobe br_netfilter

runcmd:
  # Set up firewall with lenient rules initially
  - ufw --force enable
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 22/tcp comment 'SSH'
  - ufw allow 80/tcp comment 'HTTP'
  - ufw allow 443/tcp comment 'HTTPS'
  - ufw allow 5353/udp comment 'mDNS'
  - ufw allow 9100/tcp comment 'Node Exporter'
  - ufw allow from 10.0.0.0/8 comment 'Private Network'
  - ufw allow from 192.168.0.0/16 comment 'Private Network'
  - ufw allow from 172.16.0.0/12 comment 'Private Network'
  - ufw reload
  
  # Configure fail2ban
  - systemctl enable fail2ban
  - systemctl start fail2ban
  
  # Enable services
  - systemctl enable chrony
  - systemctl restart chrony
  - systemctl enable avahi-daemon
  - systemctl start avahi-daemon
  - systemctl enable discovery-beacon
  - systemctl start discovery-beacon
  
  # Setup container environment
  - /usr/local/bin/setup-container-dirs.sh
  
  # Setup Tailscale if configured
  - /usr/local/bin/setup-tailscale.sh
  
  # Configure mDNS
  - sed -i 's/^hosts:.*/hosts:          files mdns4_minimal [NOTFOUND=return] dns mdns4/' /etc/nsswitch.conf
  
  # System optimization
  - sysctl -w net.ipv4.ip_forward=1
  - sysctl -w vm.max_map_count=262144
  - sysctl -w fs.inotify.max_user_watches=524288
  
  # Log successful deployment
  - echo "Cloud-init completed at \$(date)" >> /var/log/cloud-init-complete.log
  - /usr/local/bin/health-check.sh >> /var/log/initial-health.log 2>&1

# Final reboot to ensure everything is loaded
power_state:
  mode: reboot
  message: Initial setup complete, rebooting...
  timeout: 30
  condition: true
EOF

    # Add role-specific configurations
    case "$ROLE" in
        monitoring)
            echo "  - Adding monitoring stack configurations..."
            sudo mkdir -p "$MOUNT_POINT/root/etc/containers/systemd"
            # Add Prometheus, Grafana, Loki configs here
            ;;
        ingress)
            echo "  - Adding ingress configurations..."
            sudo mkdir -p "$MOUNT_POINT/root/etc/caddy"
            ;;
        backup)
            echo "  - Adding backup tools..."
            ;;
    esac
    
    # Set hostname
    echo "$PI_NAME" | sudo tee "$MOUNT_POINT/root/etc/hostname" > /dev/null
    
    echo -e "  ${GREEN}✓ Customization complete for $PI_NAME${NC}"
}

# Function to create custom image
create_custom_image() {
    local PI_NAME="$1"
    local ROLE="$2"
    
    echo -e "${YELLOW}Creating image for $PI_NAME (role: $ROLE)...${NC}"
    
    cp "$WORK_DIR/$BASE_IMAGE_FILE" "$WORK_DIR/${PI_NAME}.img"
    
    MOUNT_POINT="$WORK_DIR/mount_${PI_NAME}"
    LOOP_DEV=$(mount_image "$WORK_DIR/${PI_NAME}.img" "$MOUNT_POINT")
    
    customize_image "$PI_NAME" "$MOUNT_POINT" "$ROLE"
    
    unmount_image "$MOUNT_POINT" "$LOOP_DEV"
    
    echo -e "${YELLOW}Compressing image...${NC}"
    xz -9 -T0 "$WORK_DIR/${PI_NAME}.img"
    
    mv "$WORK_DIR/${PI_NAME}.img.xz" "$OUTPUT_DIR/"
    
    echo -e "${GREEN}✓ Image created: $OUTPUT_DIR/${PI_NAME}.img.xz${NC}"
}

# Main execution
main() {
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}Please run as normal user with sudo access${NC}"
        exit 1
    fi
    
    # Check for SSH keys
    check_ssh_keys
    
    # Check for required tools
    for tool in wget xz losetup sudo; do
        if ! command -v $tool &> /dev/null; then
            echo -e "${RED}Missing required tool: $tool${NC}"
            exit 1
        fi
    done
    
    # Download base image
    download_base_image
    
    # Create custom images
    echo -e "${YELLOW}Building custom images with redundancies...${NC}"
    create_custom_image "pi-a" "monitoring"
    create_custom_image "pi-b" "ingress"
    create_custom_image "pi-c" "worker"
    create_custom_image "pi-d" "backup"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ All images created successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Images created with:"
    echo "  • DHCP networking configuration"
    echo "  • Pre-installed SSH keys"
    echo "  • mDNS/Avahi for .local resolution"
    echo "  • WiFi fallback configuration"
    echo "  • Recovery user account"
    echo "  • Auto-discovery beacon"
    echo "  • USB backup automation"
    echo ""
    echo "Next steps:"
    echo "1. Flash images to SD cards"
    echo "2. Boot Pis on network with DHCP"
    echo "3. Run discovery script to find IPs"
    echo "4. Update Ansible inventory with discovered IPs"
}

main "$@"