# 📡 Static DHCP Setup Guide

## Overview

Static DHCP leases provide the best of both worlds:
- **Predictable IPs** for each Raspberry Pi
- **Central management** via DHCP server
- **Flexibility** to change IPs without touching Pis
- **Reliability** for automation and monitoring

## 🎯 IP Assignment Plan

| Hostname | Static IP | MAC Address | Role | Services |
|----------|-----------|-------------|------|----------|
| pi-a | 192.168.1.10 | (TBD) | Monitoring | Prometheus, Grafana, Loki |
| pi-b | 192.168.1.11 | (TBD) | Ingress | Traefik, Cloudflared |
| pi-c | 192.168.1.12 | (TBD) | Worker | Applications |
| pi-d | 192.168.1.13 | (TBD) | Backup | Backup, Storage |

## 📋 Quick Setup Process

### Step 1: Initial Configuration

```bash
cd pi-image-builder/

# Edit network settings if needed
nano static-dhcp-config.json

# Customize IPs for your network:
# - subnet: Your network range
# - gateway: Your router IP
# - dns_primary: Primary DNS server
# - static_leases: IP assignments for each Pi
```

### Step 2: Build and Deploy Images

```bash
# Build images with DHCP configuration
./build-custom-image-dhcp.sh

# Flash to SD cards
./images/flash-to-sdcard.sh pi-a /dev/sdb
# Repeat for pi-b, pi-c, pi-d
```

### Step 3: Boot and Collect MACs

```bash
# Boot all Pis and wait 5 minutes

# Collect MAC addresses automatically
./manage-static-dhcp.sh collect

# Or manually if needed
ssh pi@pi-a.local "ip link show eth0 | grep ether"
```

### Step 4: Configure DHCP Server

```bash
# Generate configurations for your DHCP server
./manage-static-dhcp.sh generate

# This creates configs for:
# - ISC DHCP (dhcpd.conf.generated)
# - dnsmasq (dnsmasq-dhcp.conf.generated)
# - OpenWrt (openwrt-dhcp.sh.generated)
# - pfSense (pfsense-static-dhcp.md)
```

### Step 5: Apply to Your Router/DHCP Server

#### Option A: ISC DHCP Server
```bash
# On DHCP server
sudo cp dhcpd.conf.generated /etc/dhcp/dhcpd.conf
sudo systemctl restart isc-dhcp-server
```

#### Option B: dnsmasq
```bash
# On dnsmasq server
sudo cp dnsmasq-dhcp.conf.generated /etc/dnsmasq.d/pi-cluster.conf
sudo systemctl restart dnsmasq
```

#### Option C: OpenWrt Router
```bash
# Copy script to router
scp openwrt-dhcp.sh.generated root@192.168.1.1:/tmp/

# Run on router
ssh root@192.168.1.1
sh /tmp/openwrt-dhcp.sh.generated
```

#### Option D: pfSense
Follow the guide in `pfsense-static-dhcp.md`

#### Option E: Home Router (Generic)
1. Access router web interface (usually 192.168.1.1)
2. Navigate to **DHCP Settings** or **LAN Settings**
3. Find **Static DHCP** or **DHCP Reservation**
4. Add entries for each Pi:
   - pi-a: MAC → 192.168.1.10
   - pi-b: MAC → 192.168.1.11
   - pi-c: MAC → 192.168.1.12
   - pi-d: MAC → 192.168.1.13
5. Save and apply changes

### Step 6: Reboot Pis to Get Static IPs

```bash
# Reboot all Pis
for host in pi-a pi-b pi-c pi-d; do
    ssh pi@${host}.local "sudo reboot"
done

# Wait 2 minutes for reboot
sleep 120
```

### Step 7: Verify Static Assignments

```bash
# Run optimized discovery
./discover-pis-static.sh

# Verify leases are working
./manage-static-dhcp.sh verify

# Test direct IP access
for ip in 192.168.1.10 192.168.1.11 192.168.1.12 192.168.1.13; do
    ping -c 1 $ip && echo "✓ $ip responding"
done
```

### Step 8: Update Local Configuration

```bash
# Add to /etc/hosts for reliable resolution
sudo cat hosts.static >> /etc/hosts

# SSH config is auto-updated
cat ~/.ssh/config.d/pi-cluster-static
```

## 🔧 Management Commands

### Interactive Management Menu
```bash
./manage-static-dhcp.sh
# Options:
# 1) Show configuration
# 2) Collect MAC addresses
# 3) Update network settings
# 4) Update IP assignments
# 5-8) Generate DHCP configs
# 9) Generate ALL configs
# V) Verify leases
```

### Quick Commands
```bash
# Show current config
./manage-static-dhcp.sh show

# Collect MACs from running Pis
./manage-static-dhcp.sh collect

# Generate all DHCP configs
./manage-static-dhcp.sh generate

# Verify leases are working
./manage-static-dhcp.sh verify
```

## 🚀 Optimized Discovery

The new static DHCP discovery is much faster:

```bash
# Old method (scans entire network)
time ./discover-pis.sh
# ~30-60 seconds

# New method (checks known IPs first)
time ./discover-pis-static.sh
# ~5-10 seconds
```

## 📊 Benefits of Static DHCP

### vs Dynamic DHCP
✅ **Predictable IPs** - Always know where your Pis are
✅ **Faster discovery** - No need to scan network
✅ **Reliable monitoring** - Prometheus targets don't change
✅ **Simpler configs** - Can hardcode IPs where needed

### vs Static IP Configuration
✅ **Central management** - Change IPs from DHCP server
✅ **Easier maintenance** - No need to edit Pi configs
✅ **Network flexibility** - Can move between networks
✅ **Backup DHCP** - Falls back to dynamic if needed

## 🔍 Troubleshooting

### Pis Not Getting Static IPs

1. **Check MAC addresses are correct**
```bash
./manage-static-dhcp.sh show
# Verify MACs match actual hardware
```

2. **Verify DHCP server configuration**
```bash
# Check DHCP server logs
sudo journalctl -u isc-dhcp-server -f

# Or for dnsmasq
sudo journalctl -u dnsmasq -f
```

3. **Force DHCP renewal on Pi**
```bash
ssh pi@pi-a.local
sudo dhclient -r eth0  # Release
sudo dhclient eth0     # Renew
ip addr show eth0      # Check IP
```

### Wrong IP Assigned

1. **Clear DHCP leases on server**
```bash
# ISC DHCP
sudo systemctl stop isc-dhcp-server
sudo rm /var/lib/dhcp/dhcpd.leases*
sudo systemctl start isc-dhcp-server

# dnsmasq
sudo systemctl stop dnsmasq
sudo rm /var/lib/misc/dnsmasq.leases
sudo systemctl start dnsmasq
```

2. **Check for conflicts**
```bash
# Scan for IP conflicts
for ip in 192.168.1.10 192.168.1.11 192.168.1.12 192.168.1.13; do
    arping -c 2 $ip
done
```

### Can't Connect After IP Change

1. **Clear SSH known_hosts**
```bash
for host in pi-a pi-b pi-c pi-d; do
    ssh-keygen -R $host
    ssh-keygen -R ${host}.local
    ssh-keygen -R 192.168.1.1{0,1,2,3}
done
```

2. **Update local DNS cache**
```bash
# Linux
sudo systemd-resolve --flush-caches

# macOS
sudo dscacheutil -flushcache
```

## 📝 File Reference

| File | Purpose |
|------|---------|
| `static-dhcp-config.json` | Central configuration for static leases |
| `manage-static-dhcp.sh` | Management script for static DHCP |
| `discover-pis-static.sh` | Optimized discovery for static IPs |
| `mac-addresses.txt` | Collected MAC address inventory |
| `dhcpd.conf.generated` | ISC DHCP server config |
| `dnsmasq-dhcp.conf.generated` | dnsmasq config |
| `openwrt-dhcp.sh.generated` | OpenWrt UCI commands |
| `pfsense-static-dhcp.md` | pfSense setup guide |
| `hosts.static` | /etc/hosts entries |

## 🎯 Best Practices

1. **Reserve IP ranges**
   - Static leases: `.10-.50`
   - Dynamic pool: `.100-.200`
   - Network devices: `.1-.9`

2. **Document everything**
   - Keep `static-dhcp-config.json` in git
   - Document MAC addresses
   - Note any special configs

3. **Test before production**
   - Verify on one Pi first
   - Check all services work
   - Test failover scenarios

4. **Backup configurations**
   - Save DHCP server config
   - Keep MAC inventory updated
   - Document network topology

## 🔄 Migration from Dynamic to Static

If you already have Pis running with dynamic DHCP:

```bash
# 1. Discover current setup
./discover-pis.sh

# 2. Collect MAC addresses
./manage-static-dhcp.sh collect

# 3. Configure your preferred IPs
nano static-dhcp-config.json

# 4. Generate and apply DHCP config
./manage-static-dhcp.sh generate

# 5. Apply to DHCP server
# (see Step 5 above)

# 6. Reboot Pis one at a time
for host in pi-a pi-b pi-c pi-d; do
    echo "Rebooting $host..."
    ssh pi@${host}.local "sudo reboot"
    sleep 120
    ./discover-pis-static.sh
done
```

## ✅ Validation Checklist

- [ ] All Pis have correct static IPs
- [ ] Hostnames resolve correctly
- [ ] SSH works via IP and hostname
- [ ] Services accessible on expected ports
- [ ] Ansible can reach all hosts
- [ ] Monitoring shows all targets up
- [ ] Time sync working (<100ms drift)
- [ ] Failover paths tested

## 🚨 Important Notes

1. **MAC addresses are unique** - Collect them from actual hardware
2. **IP ranges must not overlap** - Keep static and dynamic separate  
3. **Router must support static DHCP** - Most do, some call it "DHCP Reservation"
4. **DNS may cache old IPs** - Flush if needed
5. **Keep documentation updated** - MACs change if you swap hardware

---

## Quick Reference Card

```bash
# First time setup
./manage-static-dhcp.sh           # Interactive setup
./build-custom-image-dhcp.sh      # Build images
# ... flash and boot Pis ...
./manage-static-dhcp.sh collect   # Get MACs
./manage-static-dhcp.sh generate  # Create configs
# ... apply to DHCP server ...
./discover-pis-static.sh          # Verify

# Daily operations  
./discover-pis-static.sh          # Fast discovery
ssh pi-a                           # Direct access
ansible -i inventories/prod/hosts.yml.static pis -m ping

# Troubleshooting
./manage-static-dhcp.sh verify    # Check leases
./validate-deployment.sh           # Full validation
```

---

*Your static DHCP setup ensures reliable, fast, and predictable Pi cluster operations!*