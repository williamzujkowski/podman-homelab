# 🚀 Pi Cluster Quick Reference

## Ready-to-Deploy Status ✅

All components are ready for production deployment with full redundancy.

## Core Scripts (All Executable)

| Script | Purpose | Usage |
|--------|---------|-------|
| `build-custom-image-dhcp.sh` | Build Pi images with DHCP | `./build-custom-image-dhcp.sh` |
| `discover-pis.sh` | Find Pis on network | `./discover-pis.sh` |
| `setup-tailscale-redundancy.sh` | Configure VPN backup | `TAILSCALE_AUTH_KEY=tskey... ./setup-tailscale-redundancy.sh` |
| `validate-deployment.sh` | Test all systems | `./validate-deployment.sh` |

## Documentation

| File | Content | Location |
|------|---------|----------|
| `DEPLOYMENT-CHECKLIST.md` | Step-by-step deployment | `./` |
| `REDUNDANCY-FEATURES.md` | All 10 redundancy layers | `./` |
| `SENSITIVE-PI-DEPLOYMENT-GUIDE.md` | Passwords & secrets | `../` (gitignored) |

## Quick Deploy Commands

```bash
# 1. Generate SSH keys (if needed)
ssh-keygen -t ed25519 -f ~/.ssh/pi_ed25519 -N "" -C "pi-cluster"

# 2. Build images
./build-custom-image-dhcp.sh

# 3. Flash cards
./images/flash-to-sdcard.sh pi-a /dev/sdb

# 4. Boot & discover
./discover-pis.sh

# 5. Validate
./validate-deployment.sh
```

## Access Methods (Per Pi)

1. **Primary**: `ssh pi@pi-a.local` (key auth)
2. **Recovery**: `ssh recovery@pi-a.local` (password)
3. **Tailscale**: `ssh pi@pi-a-ts` (VPN)
4. **Direct IP**: Check `discovered-pis.json`

## Service Ports

- **Prometheus**: 9090 (pi-a)
- **Grafana**: 3000 (pi-a)
- **Loki**: 3100 (pi-a)
- **Node Exporter**: 9100 (all)

## Default Credentials (Change Immediately!)

- Pi user: `TempPiPass2024!Change`
- Recovery: `RecoveryAccess2024!`

## Redundancy Layers

1. ✅ SSH (3 keys + password + Tailscale)
2. ✅ Network (Ethernet + USB + WiFi)
3. ✅ DNS (mDNS + DHCP + static)
4. ✅ Time (NTS + NIST + pools)
5. ✅ Discovery (6 methods)
6. ✅ Backup (USB auto + manual)
7. ✅ Storage (multiple paths)
8. ✅ Security (firewall + fail2ban)
9. ✅ Config (cloud-init + Ansible)
10. ✅ Monitoring (Prometheus + health)

## Validation Must Pass

- Time sync <100ms ✓
- Stratum ≤3 ✓
- All SSH methods ✓
- Firewall active ✓

---
*System ready for production deployment*