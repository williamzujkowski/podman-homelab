#!/bin/bash
# Quick script to prepare and flash Pi-a image to SD card

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SD_DEVICE="/dev/sdd"
HOSTNAME="pi-a"
WORK_DIR="/tmp/pi-image-build"
BASE_IMAGE_URL="https://cdimage.ubuntu.com/ubuntu-server/jammy/daily-preinstalled/current/jammy-preinstalled-server-arm64+raspi.img.xz"
BASE_IMAGE_FILE="jammy-preinstalled-server-arm64+raspi.img"

# SSH Keys
PRIMARY_SSH_KEY="${PRIMARY_SSH_KEY:-$HOME/.ssh/pi_ed25519.pub}"
BACKUP_SSH_KEY="${BACKUP_SSH_KEY:-$HOME/.ssh/id_ed25519.pub}"
RECOVERY_SSH_KEY="${RECOVERY_SSH_KEY:-$HOME/.ssh/id_rsa.pub}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Flashing Pi-a to SD Card${NC}"
echo -e "${BLUE}========================================${NC}"

# Safety check
echo -e "\n${YELLOW}⚠️  WARNING: This will ERASE all data on $SD_DEVICE${NC}"
lsblk "$SD_DEVICE" -o NAME,SIZE,FSTYPE,MOUNTPOINT
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Create work directory
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Download base image if needed
if [ ! -f "$BASE_IMAGE_FILE" ]; then
    echo -e "\n${YELLOW}Downloading Ubuntu image...${NC}"
    if [ -f "${BASE_IMAGE_FILE}.xz" ]; then
        echo "  Extracting existing compressed image..."
        xz -d "${BASE_IMAGE_FILE}.xz"
    else
        echo "  Downloading from Ubuntu..."
        wget -q --show-progress "$BASE_IMAGE_URL" -O "${BASE_IMAGE_FILE}.xz"
        echo "  Extracting..."
        xz -d "${BASE_IMAGE_FILE}.xz"
    fi
    echo -e "${GREEN}✓ Base image ready${NC}"
else
    echo -e "${GREEN}✓ Using existing base image${NC}"
fi

# Create copy for pi-a
echo -e "\n${YELLOW}Creating Pi-a image...${NC}"
cp "$BASE_IMAGE_FILE" "pi-a.img"

# Mount the image to customize
echo -e "${YELLOW}Mounting image for customization...${NC}"
LOOP_DEV=$(sudo losetup --partscan --show --find pi-a.img)
echo "  Loop device: $LOOP_DEV"

# Wait for partitions to appear
sleep 2

# Mount boot partition
MOUNT_BOOT="/mnt/pi-boot"
MOUNT_ROOT="/mnt/pi-root"
sudo mkdir -p "$MOUNT_BOOT" "$MOUNT_ROOT"

# Mount partitions
sudo mount "${LOOP_DEV}p1" "$MOUNT_BOOT"
sudo mount "${LOOP_DEV}p2" "$MOUNT_ROOT"

echo -e "${GREEN}✓ Image mounted${NC}"

# Create cloud-init user-data
echo -e "\n${YELLOW}Configuring cloud-init...${NC}"

cat << 'EOF' | sudo tee "$MOUNT_BOOT/user-data" > /dev/null
#cloud-config
hostname: pi-a
manage_etc_hosts: true

users:
  - name: pi
    groups: [adm, sudo, podman]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: false
    passwd: $6$rounds=4096$7ZjlUGHY$ktN8bQNQweRpY2Y.6fn2VzPWegq9V7wr1R.e8WGywpqLfT0aeH1bOYrKspq.RJBj5RnXU9x3v7mfRiGkeNzJE0
    ssh_authorized_keys:
EOF

# Add SSH keys
for key_file in "$PRIMARY_SSH_KEY" "$BACKUP_SSH_KEY" "$RECOVERY_SSH_KEY"; do
    if [ -f "$key_file" ]; then
        echo "      - $(cat $key_file)" | sudo tee -a "$MOUNT_BOOT/user-data" > /dev/null
        echo "  Added key: $(basename $key_file)"
    fi
done

# Add recovery user
cat << 'EOF' | sudo tee -a "$MOUNT_BOOT/user-data" > /dev/null
  
  - name: recovery
    groups: [sudo]
    shell: /bin/bash
    sudo: ['ALL=(ALL) ALL']
    lock_passwd: false
    passwd: $6$rounds=4096$recovery$VWy4P7YQwzP7YcPM8p1GxjW5Ix5XKwfqFtt0V0f4sY9XeYfJHQDHdMmJvhqTGwPgwBZTQB5fnMQH9xuNspBXu1

packages:
  - avahi-daemon
  - chrony
  - ufw
  - fail2ban
  - unattended-upgrades
  - podman
  - curl
  - htop
  - net-tools

write_files:
  - path: /etc/chrony/chrony.conf
    content: |
      # NTP servers per CLAUDE.md requirements
      server time.cloudflare.com iburst nts
      server time.nist.gov iburst
      pool ntp.ubuntu.com iburst
      pool time.google.com iburst
      
      # Allow quick sync on boot
      makestep 0.1 3
      
      # Serve time to local network
      allow 192.168.0.0/16
      allow 10.0.0.0/8
      allow 172.16.0.0/12
      
      # Fallback to local if isolated
      local stratum 10

  - path: /etc/netplan/01-netcfg.yaml
    content: |
      network:
        version: 2
        ethernets:
          eth0:
            dhcp4: true
            dhcp4-overrides:
              send-hostname: true
              hostname: pi-a
            optional: true
        wifis:
          wlan0:
            optional: true
            dhcp4: true

runcmd:
  # System setup
  - systemctl enable avahi-daemon
  - systemctl start avahi-daemon
  - systemctl enable chrony
  - systemctl restart chrony
  
  # Firewall setup
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow ssh
  - ufw allow 9090/tcp  # Prometheus
  - ufw allow 3000/tcp  # Grafana
  - ufw allow 3100/tcp  # Loki
  - ufw allow 9100/tcp  # Node exporter
  - ufw allow 5353/udp  # mDNS
  - ufw allow from 10.0.0.0/8
  - ufw allow from 192.168.0.0/16
  - ufw allow from 172.16.0.0/12
  - echo "y" | ufw enable
  
  # Create directories
  - mkdir -p /home/pi/volumes
  - mkdir -p /home/pi/backup
  - chown -R pi:pi /home/pi/volumes /home/pi/backup
  
  # Configure Podman
  - loginctl enable-linger pi
  - mkdir -p /home/pi/.config/containers/systemd
  - chown -R pi:pi /home/pi/.config

final_message: "Pi-a ready after $UPTIME seconds"
EOF

echo -e "${GREEN}✓ Cloud-init configured${NC}"

# Unmount
echo -e "\n${YELLOW}Unmounting image...${NC}"
sudo umount "$MOUNT_BOOT"
sudo umount "$MOUNT_ROOT"
sudo losetup -d "$LOOP_DEV"

# Flash to SD card
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}   Flashing to SD Card${NC}"
echo -e "${BLUE}========================================${NC}"

# Unmount any existing partitions
echo -e "${YELLOW}Unmounting SD card partitions...${NC}"
sudo umount ${SD_DEVICE}* 2>/dev/null || true

# Flash the image
echo -e "${YELLOW}Writing image to $SD_DEVICE...${NC}"
echo "This will take several minutes..."

sudo dd if=pi-a.img of="$SD_DEVICE" bs=4M status=progress conv=fsync

echo -e "\n${GREEN}✓ Image written successfully${NC}"

# Sync and eject
echo -e "${YELLOW}Syncing and ejecting...${NC}"
sync
sudo eject "$SD_DEVICE"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}   ✓ Pi-a SD Card Ready!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo "1. Remove SD card and insert into Pi-a"
echo "2. Connect Ethernet cable"
echo "3. Power on Pi-a"
echo "4. Wait 5-10 minutes for first boot"
echo "5. Discover Pi: ./discover-pis-static.sh"
echo ""
echo "Default access:"
echo "  ssh pi@pi-a.local"
echo "  ssh pi@192.168.1.10 (after static DHCP setup)"
echo ""
echo "Services on Pi-a:"
echo "  • Prometheus (port 9090)"
echo "  • Grafana (port 3000)"
echo "  • Loki (port 3100)"