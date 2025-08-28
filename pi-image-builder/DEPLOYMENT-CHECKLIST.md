# 📋 Pi Cluster Deployment Checklist

## ✅ Pre-Deployment Preparation

### 1. Environment Setup
- [ ] **SSH Keys Generated**
  ```bash
  ssh-keygen -t ed25519 -f ~/.ssh/pi_ed25519 -C "pi-cluster-key"
  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "backup-key"
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -C "recovery-key"
  ```

- [ ] **Export SSH Key Paths**
  ```bash
  export PRIMARY_SSH_KEY=~/.ssh/pi_ed25519.pub
  export BACKUP_SSH_KEY=~/.ssh/id_ed25519.pub
  export RECOVERY_SSH_KEY=~/.ssh/id_rsa.pub
  ```

- [ ] **Install Required Tools**
  ```bash
  sudo apt-get update
  sudo apt-get install -y qemu-utils cloud-image-utils xz-utils jq avahi-utils sshpass
  ```

- [ ] **WiFi Credentials** (optional)
  ```bash
  export WIFI_SSID="YourWiFiNetwork"
  export WIFI_PASSWORD="YourSecurePassword"
  ```

- [ ] **Tailscale Auth Key** (optional but recommended)
  ```bash
  # Get from https://login.tailscale.com/admin/settings/authkeys
  export TAILSCALE_AUTH_KEY="tskey-auth-..."
  ```

### 2. Network Configuration (Choose One)

#### Option A: Static DHCP (Recommended)
- [ ] **Configure static DHCP settings**
  ```bash
  nano static-dhcp-config.json
  # Set your network subnet, IPs, etc.
  ```
- [ ] **Plan IP assignments**
  - pi-a: 192.168.1.10 (Monitoring)
  - pi-b: 192.168.1.11 (Ingress)
  - pi-c: 192.168.1.12 (Worker)
  - pi-d: 192.168.1.13 (Backup)

#### Option B: Dynamic DHCP
- [ ] Use default DHCP discovery (slower but works anywhere)

### 3. Hardware Preparation
- [ ] 4x Raspberry Pi 4B (8GB recommended)
- [ ] 4x microSD cards (32GB+ Class 10/A1)
- [ ] 4x USB-C power supplies (3A minimum)
- [ ] 1x Gigabit switch (5+ ports)
- [ ] 5x Ethernet cables
- [ ] 1x SD card reader
- [ ] Labels for Pis (pi-a, pi-b, pi-c, pi-d)

## 🏗️ Image Building Phase

### 4. Build Custom Images
- [ ] **Navigate to build directory**
  ```bash
  cd pi-image-builder/
  ```

- [ ] **Review build configuration**
  ```bash
  # Check script has your SSH keys
  grep "SSH_KEY" build-custom-image-dhcp.sh
  ```

- [ ] **Run image builder**
  ```bash
  ./build-custom-image-dhcp.sh
  ```
  Expected output:
  - ✓ Base image downloaded
  - ✓ Image mounted
  - ✓ Cloud-init configured
  - ✓ SSH keys installed
  - ✓ Recovery user created
  - ✓ Network redundancy configured
  - ✓ 4 images created (pi-a.img, pi-b.img, pi-c.img, pi-d.img)

### 5. Flash SD Cards
- [ ] **Flash each card**
  ```bash
  # Insert SD card for pi-a
  ./images/flash-to-sdcard.sh pi-a /dev/sdX  # Replace X with your device
  
  # Repeat for pi-b, pi-c, pi-d
  ```

- [ ] **Verify flashing**
  - Check for "success" message
  - Eject and re-insert to verify partitions

## 🚀 Initial Boot Phase

### 6. Physical Setup
- [ ] Insert SD cards into correct Pis
- [ ] Connect Ethernet cables to switch
- [ ] Label each Pi (pi-a, pi-b, pi-c, pi-d)
- [ ] Connect power supplies
- [ ] **Wait 5-10 minutes for first boot**
  - Cloud-init runs
  - System updates apply
  - Services configure

### 7. Discovery & Verification

#### For Static DHCP:
- [ ] **Collect MAC addresses and configure DHCP**
  ```bash
  # Collect MACs from running Pis
  ./manage-static-dhcp.sh collect
  
  # Generate DHCP server config
  ./manage-static-dhcp.sh generate
  
  # Apply to your DHCP server, then reboot Pis
  ```

- [ ] **Run optimized discovery**
  ```bash
  ./discover-pis-static.sh
  ```
  Expected results (5-10 seconds):
  - ✓ Static IP verification (4 Pis)
  - ✓ MAC address collection
  - ✓ Generated files:
    - `discovered-pis.json`
    - `~/.ssh/config.d/pi-cluster-static`
    - `../ansible/inventories/prod/hosts.yml.static`
    - `hosts.static`

#### For Dynamic DHCP:
- [ ] **Run standard discovery**
  ```bash
  ./discover-pis.sh
  ```
  Expected results (30-60 seconds):
  - ✓ mDNS resolution (4 Pis)
  - ✓ SSH key authentication
  - ✓ Generated files:
    - `discovered-pis.json`
    - `~/.ssh/config.d/pi-cluster`
    - `../ansible/inventories/prod/hosts.yml.dynamic`

- [ ] **Test SSH access**
  ```bash
  ssh pi-a hostname
  ssh pi-b hostname
  ssh pi-c hostname
  ssh pi-d hostname
  ```

## 🔒 Redundancy Configuration

### 8. Setup Tailscale (Optional but Recommended)
- [ ] **Configure Tailscale redundancy**
  ```bash
  export TAILSCALE_AUTH_KEY="tskey-auth-..."
  ./setup-tailscale-redundancy.sh
  ```
  Verifies:
  - Tailscale installed on all Pis
  - SSH failover configured
  - VPN connectivity established

### 9. Validate Deployment
- [ ] **Run full validation suite**
  ```bash
  # For static DHCP setup:
  ./validate-static-deployment.sh
  
  # For dynamic DHCP setup:
  ./validate-deployment.sh
  ```
  
  Must pass (critical):
  - [ ] mDNS resolution (all 4 Pis)
  - [ ] SSH key authentication
  - [ ] Time sync (<100ms drift, stratum ≤3)
  - [ ] Firewall enabled
  
  Should pass (important):
  - [ ] Node exporters running
  - [ ] Recovery user access
  - [ ] Backup directories created
  - [ ] Podman installed
  
  Nice to have:
  - [ ] Tailscale connectivity
  - [ ] WiFi backup configured
  - [ ] USB backup scripts

## 📦 Service Deployment

### 10. Deploy Core Services
- [ ] **Change to Ansible directory**
  ```bash
  cd ../ansible/
  ```

- [ ] **Test connectivity**
  ```bash
  ansible -i inventories/prod/hosts.yml.dynamic pis -m ping
  ```

- [ ] **Bootstrap Pis**
  ```bash
  ansible-playbook -i inventories/prod/hosts.yml.dynamic playbooks/00-bootstrap.yml
  ```

- [ ] **Deploy monitoring stack**
  ```bash
  ansible-playbook -i inventories/prod/hosts.yml.dynamic playbooks/01-monitoring.yml
  ```

### 11. Verify Services
- [ ] **Prometheus** (pi-a)
  ```bash
  curl -s http://pi-a.local:9090/-/ready
  ```

- [ ] **Grafana** (pi-a)
  ```bash
  curl -s http://pi-a.local:3000/api/health
  ```

- [ ] **Loki** (pi-a)
  ```bash
  curl -s http://pi-a.local:3100/ready
  ```

- [ ] **Node Exporters** (all)
  ```bash
  for host in pi-a pi-b pi-c pi-d; do
    curl -s http://${host}.local:9100/metrics | head -1
  done
  ```

## 🔐 Security Hardening

### 12. Change Default Passwords
- [ ] **Update pi user password**
  ```bash
  for host in pi-a pi-b pi-c pi-d; do
    ssh $host 'passwd'
  done
  ```

- [ ] **Update recovery user password**
  ```bash
  for host in pi-a pi-b pi-c pi-d; do
    ssh $host 'sudo passwd recovery'
  done
  ```

### 13. Verify Security
- [ ] UFW firewall active on all nodes
- [ ] fail2ban running
- [ ] Unattended upgrades configured
- [ ] SSH key-only auth (after password change)

## 🔄 Backup & Recovery

### 14. Test Backup Mechanisms
- [ ] **USB backup** (insert USB drive)
  - Check `/mnt/usb-backup/` for automatic backup
  - Verify config files copied

- [ ] **Manual backup test**
  ```bash
  ssh pi-a '/usr/local/bin/backup-configs.sh'
  ```

### 15. Document Recovery Info
- [ ] Record Tailscale device names
- [ ] Note DHCP-assigned IPs
- [ ] Save SSH key locations
- [ ] Document any custom configurations

## 📊 Monitoring Setup

### 16. Configure Dashboards
- [ ] Access Grafana: http://pi-a.local:3000
- [ ] Import Node Exporter dashboard (ID: 1860)
- [ ] Configure alerting rules
- [ ] Test log aggregation in Loki

## ✅ Final Verification

### 17. Complete System Test
- [ ] **Run final validation**
  ```bash
  # For static DHCP:
  ./validate-static-deployment.sh
  
  # For dynamic DHCP:
  ./validate-deployment.sh
  ```
  
- [ ] **Check time sync** (CRITICAL)
  ```bash
  for host in pi-a pi-b pi-c pi-d; do
    ssh $host 'chronyc tracking | grep "System time"'
  done
  ```
  Must show <100ms offset

- [ ] **Test failover**
  - Disconnect pi-a ethernet
  - Verify WiFi takeover
  - Test Tailscale access

## 🎉 Deployment Complete!

### Success Criteria
✅ All 4 Pis accessible via SSH  
✅ Time synchronized (<100ms drift)  
✅ Monitoring stack operational  
✅ Multiple access paths configured  
✅ Backup mechanisms in place  
✅ Security hardening applied  

### Next Steps
1. Commit configuration to git (excluding sensitive files)
2. Document any site-specific customizations
3. Schedule regular backup verification
4. Monitor system health via Grafana

### Troubleshooting Resources
- Discovery issues: Check `./discover-pis.sh` output
- SSH problems: Try recovery user or Tailscale
- Time sync: Verify NTP servers in chrony config
- Service failures: Check journalctl logs

---

## Quick Recovery Commands

```bash
# If primary SSH fails
ssh recovery@pi-a.local  # Password: RecoveryAccess2024!

# If network fails
ssh pi-a-ts  # Via Tailscale

# Force rediscovery
./discover-pis.sh

# Emergency validation
./validate-deployment.sh
```

## Support Files
- `REDUNDANCY-FEATURES.md` - All redundancy mechanisms
- `SENSITIVE-PI-DEPLOYMENT-GUIDE.md` - Sensitive information
- `discovered-pis.json` - Last discovery results
- `validation-*.log` - Validation history

---

*Generated for: Podman Homelab Pi Cluster v1.0*