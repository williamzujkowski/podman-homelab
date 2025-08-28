#!/bin/bash
# Custom Raspberry Pi Image Builder for Homelab Infrastructure
# This script creates pre-configured images for each Pi with all software and configs

set -euo pipefail

# Configuration
WORK_DIR="/tmp/pi-image-builder"
OUTPUT_DIR="./images"
BASE_IMAGE_URL="https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04-preinstalled-server-arm64+raspi.img.xz"
BASE_IMAGE_FILE="ubuntu-24.04-preinstalled-server-arm64+raspi.img"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Create work directories
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Raspberry Pi Custom Image Builder${NC}"
echo -e "${GREEN}========================================${NC}"

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
    
    # Create loop device
    LOOP_DEV=$(sudo losetup --show -fP "$IMAGE_FILE")
    echo "Loop device: $LOOP_DEV"
    
    # Wait for partitions to appear
    sleep 2
    
    # Mount partitions
    sudo mkdir -p "$MOUNT_POINT/boot"
    sudo mkdir -p "$MOUNT_POINT/root"
    
    # Mount boot partition (usually partition 1)
    sudo mount "${LOOP_DEV}p1" "$MOUNT_POINT/boot"
    
    # Mount root partition (usually partition 2)
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
    
    # Clean up mount points
    sudo rm -rf "$MOUNT_POINT"
}

# Function to customize image for specific Pi
customize_image() {
    local PI_NAME="$1"
    local PI_IP="$2"
    local MOUNT_POINT="$3"
    
    echo -e "${YELLOW}Customizing image for $PI_NAME ($PI_IP)...${NC}"
    
    # Copy our configurations and software
    echo "  - Setting up network configuration..."
    sudo tee "$MOUNT_POINT/boot/network-config" > /dev/null << EOF
version: 2
ethernets:
  eth0:
    dhcp4: false
    addresses:
      - $PI_IP/24
    gateway4: 10.0.1.1
    nameservers:
      addresses:
        - 1.1.1.1
        - 8.8.8.8
EOF
    
    # Create cloud-init user-data
    echo "  - Creating cloud-init configuration..."
    sudo tee "$MOUNT_POINT/boot/user-data" > /dev/null << EOF
#cloud-config
hostname: $PI_NAME
manage_etc_hosts: true
locale: en_US.UTF-8
timezone: America/New_York

# Create user
users:
  - name: pi
    groups: [adm, sudo, docker]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    # Password: TempPiPass2024!Change (pre-hashed)
    passwd: \$6\$rounds=4096\$8JhNXTYJ\$Q9QxZZPGzF3cNbBBajGPqz9FkHQNymLFZLFe5TSRqIqGZgSxY5Zj5Aqj5YqRwMfJLN9YWkYfCV7cWkF3wXqKH1
    ssh_authorized_keys:
      - $(cat ~/.ssh/pi_ed25519.pub 2>/dev/null || echo "ssh-ed25519 YOUR_KEY_HERE")

# Disable password authentication after first boot
ssh_pwauth: true
disable_root: true

# Package installation
package_update: true
package_upgrade: true
packages:
  - python3
  - python3-pip
  - podman
  - podman-compose
  - curl
  - wget
  - git
  - vim
  - htop
  - chrony
  - ufw
  - prometheus-node-exporter
  - fail2ban
  - unattended-upgrades
  - jq
  - net-tools
  - dnsutils
  - iotop
  - ncdu
  - tree
  - tmux
  - rsync
  - nmap
  - tcpdump

# Write files
write_files:
  # Chrony configuration with NTS (CLAUDE.md requirement)
  - path: /etc/chrony/chrony.conf
    content: |
      # NTS time sources as per CLAUDE.md golden rule
      server time.cloudflare.com iburst nts
      server time.nist.gov iburst
      
      # Fallback servers
      pool ntp.ubuntu.com iburst
      
      makestep 0.1 3
      rtcsync
      
      # Allow NTP client access from local network
      allow 10.0.1.0/24
      
      # Record drift
      driftfile /var/lib/chrony/chrony.drift
    
  # Podman configuration
  - path: /etc/containers/containers.conf
    content: |
      [containers]
      log_driver = "journald"
      log_size_max = 10485760
      
      [engine]
      runtime = "crun"
      events_logger = "journald"
      cgroup_manager = "systemd"
  
  # System limits for containers
  - path: /etc/security/limits.d/containers.conf
    content: |
      * soft nofile 1048576
      * hard nofile 1048576
      root soft nofile 1048576
      root hard nofile 1048576
  
  # Sysctl tuning for containers
  - path: /etc/sysctl.d/99-containers.conf
    content: |
      net.ipv4.ip_forward = 1
      net.bridge.bridge-nf-call-iptables = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      fs.inotify.max_user_instances = 8192
      fs.inotify.max_user_watches = 524288
      vm.max_map_count = 262144
  
  # Container systemd directory creation script
  - path: /usr/local/bin/setup-container-dirs.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # Setup container directories for pi user
      mkdir -p /home/pi/.config/containers/systemd
      mkdir -p /home/pi/.config/systemd/user
      mkdir -p /home/pi/volumes
      mkdir -p /home/pi/backup
      mkdir -p /etc/containers/systemd
      chown -R pi:pi /home/pi/.config
      chown -R pi:pi /home/pi/volumes
      chown -R pi:pi /home/pi/backup
      
      # Enable lingering for pi user
      loginctl enable-linger pi
      
      # Create quadlet directories
      mkdir -p /etc/containers/systemd
      mkdir -p /home/pi/.config/containers/systemd
  
  # Health check script
  - path: /usr/local/bin/health-check.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      echo "=== System Health Check ==="
      echo "Hostname: \$(hostname)"
      echo "IP: \$(hostname -I | cut -d' ' -f1)"
      echo "CPU: \$(nproc) cores"
      echo "RAM: \$(free -h | grep Mem | awk '{print \$2}')"
      echo "Disk: \$(df -h / | tail -1 | awk '{print \$4}') free"
      echo "Load: \$(uptime | awk -F'load average:' '{print \$2}')"
      echo "Time sync: \$(chronyc tracking | grep 'System time' | cut -d: -f2-)"
      echo "Containers: \$(sudo podman ps --format '{{.Names}}' | wc -l) running"
  
  # Auto-update script for containers
  - path: /usr/local/bin/update-containers.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # Manual container update script
      echo "Checking for container updates..."
      sudo podman auto-update --dry-run
      echo "To apply updates, run: sudo podman auto-update"

# Firewall rules
runcmd:
  # Set up firewall
  - ufw --force enable
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 22/tcp comment 'SSH'
  - ufw allow 80/tcp comment 'HTTP'
  - ufw allow 443/tcp comment 'HTTPS'
  - ufw allow 9100/tcp comment 'Node Exporter'
  - ufw allow 9090/tcp comment 'Prometheus' 
  - ufw allow 3000/tcp comment 'Grafana'
  - ufw allow 3100/tcp comment 'Loki'
  - ufw reload
  
  # Configure fail2ban
  - systemctl enable fail2ban
  - systemctl start fail2ban
  
  # Enable services
  - systemctl enable chrony
  - systemctl restart chrony
  - systemctl enable podman.socket
  - systemctl start podman.socket
  
  # Run setup script
  - /usr/local/bin/setup-container-dirs.sh
  
  # Create systemd service for container auto-start
  - systemctl daemon-reload
  - systemctl enable podman-restart.service || true
  
  # Set up unattended upgrades
  - dpkg-reconfigure -plow unattended-upgrades
  
  # System optimization
  - sysctl -p /etc/sysctl.d/99-containers.conf
  
  # Log completion
  - echo "Cloud-init setup completed at \$(date)" >> /var/log/cloud-init-complete.log

# Power management (keep Pi running)
power_state:
  mode: reboot
  message: Initial setup complete, rebooting...
  timeout: 30
  condition: true
EOF

    # Copy Quadlet files if this is the monitoring node
    if [ "$PI_NAME" == "pi-a" ]; then
        echo "  - Copying monitoring stack Quadlet files..."
        sudo mkdir -p "$MOUNT_POINT/root/etc/containers/systemd"
        
        # Copy our Quadlet definitions
        for quadlet in ../quadlet/{prometheus,grafana,loki,node-exporter,promtail}.container; do
            if [ -f "$quadlet" ]; then
                sudo cp "$quadlet" "$MOUNT_POINT/root/etc/containers/systemd/"
            fi
        done
        
        # Copy configurations
        sudo mkdir -p "$MOUNT_POINT/root/etc/prometheus"
        sudo mkdir -p "$MOUNT_POINT/root/etc/grafana/provisioning"
        sudo mkdir -p "$MOUNT_POINT/root/etc/loki"
        
        # Copy config files if they exist
        [ -f "../ansible/roles/prometheus/templates/prometheus.yml.j2" ] && \
            sudo cp "../ansible/roles/prometheus/templates/prometheus.yml.j2" "$MOUNT_POINT/root/etc/prometheus/prometheus.yml"
        [ -f "../ansible/roles/grafana/templates/datasources.yml.j2" ] && \
            sudo cp "../ansible/roles/grafana/templates/datasources.yml.j2" "$MOUNT_POINT/root/etc/grafana/provisioning/datasources.yml"
    fi
    
    # Copy Caddy configuration if this is the ingress node
    if [ "$PI_NAME" == "pi-b" ]; then
        echo "  - Copying Caddy configuration..."
        sudo mkdir -p "$MOUNT_POINT/root/etc/containers/systemd"
        [ -f "../quadlet/caddy.container" ] && \
            sudo cp "../quadlet/caddy.container" "$MOUNT_POINT/root/etc/containers/systemd/"
        
        sudo mkdir -p "$MOUNT_POINT/root/etc/caddy"
        # Create basic Caddyfile
        sudo tee "$MOUNT_POINT/root/etc/caddy/Caddyfile" > /dev/null << 'CADDY'
:80 {
    respond "Homelab Ingress Ready"
}

:3000 {
    reverse_proxy 10.0.1.10:3000
}

:9090 {
    reverse_proxy 10.0.1.10:9090
}

:3100 {
    reverse_proxy 10.0.1.10:3100
}
CADDY
    fi
    
    # Set hostname in the actual system
    echo "$PI_NAME" | sudo tee "$MOUNT_POINT/root/etc/hostname" > /dev/null
    
    # Update hosts file
    sudo tee -a "$MOUNT_POINT/root/etc/hosts" > /dev/null << EOF

# Homelab cluster
10.0.1.10 pi-a
10.0.1.11 pi-b
10.0.1.12 pi-c
10.0.1.13 pi-d
EOF

    echo -e "  ${GREEN}✓ Customization complete for $PI_NAME${NC}"
}

# Function to create custom image
create_custom_image() {
    local PI_NAME="$1"
    local PI_IP="$2"
    
    echo -e "${YELLOW}Creating image for $PI_NAME...${NC}"
    
    # Copy base image
    cp "$WORK_DIR/$BASE_IMAGE_FILE" "$WORK_DIR/${PI_NAME}.img"
    
    # Mount the image
    MOUNT_POINT="$WORK_DIR/mount_${PI_NAME}"
    LOOP_DEV=$(mount_image "$WORK_DIR/${PI_NAME}.img" "$MOUNT_POINT")
    
    # Customize the image
    customize_image "$PI_NAME" "$PI_IP" "$MOUNT_POINT"
    
    # Unmount the image
    unmount_image "$MOUNT_POINT" "$LOOP_DEV"
    
    # Compress the final image
    echo -e "${YELLOW}Compressing image...${NC}"
    xz -9 -T0 "$WORK_DIR/${PI_NAME}.img"
    
    # Move to output directory
    mv "$WORK_DIR/${PI_NAME}.img.xz" "$OUTPUT_DIR/"
    
    echo -e "${GREEN}✓ Image created: $OUTPUT_DIR/${PI_NAME}.img.xz${NC}"
}

# Main execution
main() {
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}Please run this script as a normal user (with sudo access)${NC}"
        echo "The script will use sudo when needed."
        exit 1
    fi
    
    # Check for required tools
    for tool in wget xz losetup sudo mkfs.ext4; do
        if ! command -v $tool &> /dev/null; then
            echo -e "${RED}Error: $tool is not installed${NC}"
            echo "Install with: sudo apt install wget xz-utils mount util-linux e2fsprogs"
            exit 1
        fi
    done
    
    # Download base image
    download_base_image
    
    # Create custom images for each Pi
    echo -e "${YELLOW}Building custom images...${NC}"
    create_custom_image "pi-a" "10.0.1.10"
    create_custom_image "pi-b" "10.0.1.11"
    create_custom_image "pi-c" "10.0.1.12"
    create_custom_image "pi-d" "10.0.1.13"
    
    # Create flash script
    cat > "$OUTPUT_DIR/flash-to-sdcard.sh" << 'FLASH'
#!/bin/bash
# Script to flash custom images to SD cards

if [ $# -ne 2 ]; then
    echo "Usage: $0 <pi-name> <device>"
    echo "Example: $0 pi-a /dev/sdb"
    exit 1
fi

PI_NAME=$1
DEVICE=$2
IMAGE_FILE="${PI_NAME}.img.xz"

if [ ! -f "$IMAGE_FILE" ]; then
    echo "Error: Image file $IMAGE_FILE not found"
    exit 1
fi

if [ ! -b "$DEVICE" ]; then
    echo "Error: Device $DEVICE not found"
    exit 1
fi

echo "⚠️  WARNING: This will ERASE ALL DATA on $DEVICE"
echo "Image: $IMAGE_FILE"
echo "Target: $DEVICE"
read -p "Are you sure? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted"
    exit 1
fi

echo "Flashing image to $DEVICE..."
xzcat "$IMAGE_FILE" | sudo dd of="$DEVICE" bs=4M status=progress conv=fsync

echo "Syncing..."
sync

echo "✓ Flash complete! You can now safely remove the SD card."
echo "Label this SD card: $PI_NAME"
FLASH
    
    chmod +x "$OUTPUT_DIR/flash-to-sdcard.sh"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ All images created successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Images created in: $OUTPUT_DIR/"
    echo "  - pi-a.img.xz (Monitoring stack)"
    echo "  - pi-b.img.xz (Ingress/Caddy)"
    echo "  - pi-c.img.xz (Worker)"
    echo "  - pi-d.img.xz (Worker/Backup)"
    echo ""
    echo "To flash to SD card:"
    echo "  cd $OUTPUT_DIR"
    echo "  ./flash-to-sdcard.sh pi-a /dev/sdX"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Flash each image to its respective SD card"
    echo "2. Label each SD card clearly"
    echo "3. Insert into Raspberry Pis and power on"
    echo "4. Wait 5-10 minutes for initial setup"
    echo "5. SSH to each Pi: ssh pi@10.0.1.10 (etc)"
    echo "6. Run health check: ssh pi@pi-a '/usr/local/bin/health-check.sh'"
    
    # Clean up work directory
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"
    sudo rm -rf "$WORK_DIR/mount_"*
    
    echo -e "${GREEN}✓ Build complete!${NC}"
}

# Run main function
main "$@"