# Raspberry Pi Custom Image Builder

This directory contains tools to create pre-configured Raspberry Pi images with all software and configurations pre-loaded, eliminating most manual setup steps.

## 🎯 Benefits of Pre-built Images

### Why Use Custom Images?

1. **Zero Manual Configuration**: Everything is pre-configured
2. **Consistent Deployment**: Every Pi gets identical base setup
3. **Fast Deployment**: Boot and go - no waiting for package installs
4. **Pre-installed Software**: All required packages included
5. **Security Hardening**: Security settings applied from first boot
6. **Network Ready**: Static IPs and DNS pre-configured
7. **Service Ready**: Quadlet files and configs included

### Time Savings

- **Traditional Setup**: 45-60 minutes per Pi
- **With Custom Images**: 5-10 minutes per Pi
- **Total for 4 Pis**: 4 hours → 30 minutes

## 📦 What's Included in Images

### All Pis Get:
- Ubuntu Server 24.04 LTS for ARM64
- Static IP configuration
- Chrony with NTS time sync (per CLAUDE.md)
- Podman & container tools
- Python3 and Ansible dependencies
- Security hardening (UFW, fail2ban)
- SSH key authentication ready
- Health check scripts
- System optimization for containers
- Monitoring tools (htop, iotop, etc.)

### Pi-Specific Configurations:
- **pi-a**: Prometheus, Grafana, Loki Quadlet files
- **pi-b**: Caddy ingress configuration
- **pi-c**: Worker node optimization
- **pi-d**: Backup scripts and tools

## 🚀 Quick Start

### Prerequisites

On your build machine:
```bash
# Install required tools
sudo apt update
sudo apt install -y wget xz-utils qemu-user-static cloud-image-utils

# Install sshpass for automation (optional)
sudo apt install -y sshpass
```

### Building Images

#### Method 1: Direct Build (Recommended)
```bash
cd pi-image-builder
chmod +x build-custom-image.sh

# Build all images (takes ~20-30 minutes)
./build-custom-image.sh
```

#### Method 2: Container Build (Safer)
```bash
cd pi-image-builder

# Build the builder container
podman build -f Dockerfile.image-builder -t pi-builder .

# Run the build
podman run --privileged -v ./images:/build/images pi-builder
```

### Output

After building, you'll have:
```
images/
├── pi-a.img.xz    # Monitoring stack node
├── pi-b.img.xz    # Ingress/Caddy node
├── pi-c.img.xz    # Worker node
├── pi-d.img.xz    # Worker/Backup node
└── flash-to-sdcard.sh  # Helper script
```

## 💾 Flashing to SD Cards

### Using Raspberry Pi Imager (GUI)

1. Open Raspberry Pi Imager
2. Choose "Use custom" for OS
3. Select the appropriate `.img.xz` file
4. Choose your SD card
5. **IMPORTANT**: Click "NO" when asked about OS customization
6. Write the image
7. Label the SD card physically

### Using Command Line

```bash
cd images

# Flash pi-a image to SD card at /dev/sdb
./flash-to-sdcard.sh pi-a /dev/sdb

# Repeat for each Pi
./flash-to-sdcard.sh pi-b /dev/sdc
# etc...
```

### Using dd directly

```bash
# BE VERY CAREFUL - this will erase the target device!
xzcat pi-a.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

## 🔌 Physical Deployment

1. **Insert SD cards** into respective Pis
2. **Connect Ethernet** cables
3. **Power on** Pis (one at a time, wait 30s between)
4. **Wait 5-10 minutes** for cloud-init to complete
5. **Run quick deploy**:
   ```bash
   ./quick-deploy.sh
   ```

## 🔑 Default Credentials

**CHANGE THESE IMMEDIATELY AFTER DEPLOYMENT!**

- Username: `pi`
- Password: `TempPiPass2024!Change`
- Grafana: `admin` / `admin`

## 🏗️ Customization

### Modify Network Settings

Edit `build-custom-image.sh` and change:
```bash
# Line ~120 - Network configuration
addresses:
  - $PI_IP/24
gateway4: 10.0.1.1  # Your gateway
```

### Change Packages

Edit the `packages:` section in cloud-init:
```yaml
packages:
  - your-package-here
  - another-package
```

### Add Files

Add to `write_files:` section:
```yaml
- path: /path/to/file
  content: |
    Your content here
  permissions: '0644'
```

## 🔍 Verification

After deployment, verify with:

```bash
# Check all nodes
for host in pi-a pi-b pi-c pi-d; do
    echo "=== $host ==="
    ssh $host '/usr/local/bin/health-check.sh'
done

# Check services
curl http://10.0.1.10:9090/-/ready  # Prometheus
curl http://10.0.1.10:3000/api/health  # Grafana
curl http://10.0.1.10:3100/ready  # Loki
```

## 📊 Image Contents

### File Structure Added

```
/etc/
├── chrony/chrony.conf         # NTS time sync
├── containers/
│   ├── containers.conf        # Podman config
│   └── systemd/               # Quadlet files
├── security/limits.d/         # Container limits
├── sysctl.d/                  # Kernel tuning
└── hosts                      # Cluster hosts

/usr/local/bin/
├── health-check.sh            # System health
├── setup-container-dirs.sh    # Directory setup
└── update-containers.sh       # Update helper

/home/pi/
├── .config/containers/        # User container config
├── volumes/                   # Container volumes
└── backup/                    # Backup location
```

### Services Pre-configured

- **Chrony**: NTP with NTS to Cloudflare/NIST
- **UFW**: Firewall with required ports open
- **Fail2ban**: Brute force protection
- **Podman**: Container runtime with systemd integration
- **Node Exporter**: System metrics (all nodes)

## 🛠️ Troubleshooting

### Image Build Fails

```bash
# Check available disk space
df -h

# Run with debug
bash -x build-custom-image.sh

# Try building single image
./build-custom-image.sh pi-a
```

### SD Card Not Recognized

```bash
# List block devices
lsblk

# Check device path
sudo fdisk -l

# May need to unmount first
sudo umount /dev/sdX*
```

### Pi Won't Boot

1. Verify SD card is properly flashed
2. Check power supply (3A recommended)
3. Try different SD card
4. Connect HDMI to see boot messages

### Can't SSH After Boot

```bash
# Check if Pi is on network
nmap -sn 10.0.1.0/24

# Try with password first
ssh pi@10.0.1.10
# Password: TempPiPass2024!Change

# Check cloud-init logs (if you can access)
ssh pi@10.0.1.10 'sudo cat /var/log/cloud-init-output.log'
```

## 🔄 Updates

To update images with new software:

1. Modify `build-custom-image.sh`
2. Rebuild images
3. Reflash SD cards
4. Redeploy

Or use Ansible for running systems:
```bash
ansible-playbook -i inventories/prod/hosts.yml playbooks/update.yml
```

## 📝 Notes

- Images are ~2-3GB compressed, ~8GB uncompressed
- Build requires ~20GB free disk space
- Use Class 10 or better SD cards
- Label SD cards immediately after flashing
- Keep backup of images after successful deployment

## 🚨 Security Reminder

These images contain:
- Default passwords (must be changed)
- Network configurations
- SSH configurations

**Do not share images publicly without removing sensitive data!**

---

*Created for Raspberry Pi 4B cluster deployment*
*Optimized for Ubuntu Server 24.04 LTS ARM64*