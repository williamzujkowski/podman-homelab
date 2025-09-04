# Cloudflare Integration for Homelab Infrastructure

## Overview
This guide details the complete Cloudflare integration for the homelab, providing secure certificate management and DNS configuration for internal services while ensuring they remain inaccessible from the public internet.

## Architecture

```
Internet → Cloudflare → [BLOCKED]
                           ↓
                    Local Network Only
                           ↓
                    192.168.1.11 (pi-b)
                    Caddy Ingress with
                    Cloudflare Origin Cert
                           ↓
        ┌──────────────────┼──────────────────┐
        ↓                  ↓                  ↓
   192.168.1.12        192.168.1.10      192.168.1.13
     (pi-a)              (pi-c)            (pi-d)
   Monitoring           Workers           Storage
```

## Certificate Strategy

### 1. Cloudflare Origin CA (Recommended)
- **Duration**: 15-year certificates
- **Coverage**: `*.homelab.grenlan.com`, `homelab.grenlan.com`
- **Management**: No renewal needed for 15 years
- **Security**: Trusted by Cloudflare, perfect for internal services

### 2. Implementation Plan

#### Phase 1: DNS Configuration
```bash
# Add these A records in Cloudflare Dashboard (DO NOT PROXY)
homelab.grenlan.com         → 192.168.1.11  (DNS only - grey cloud)
*.homelab.grenlan.com       → 192.168.1.11  (DNS only - grey cloud)
```

**Important**: Keep these records **unproxied** (grey cloud) to ensure they resolve to internal IPs only.

#### Phase 2: Generate Origin Certificate
1. Log into Cloudflare Dashboard
2. Navigate to SSL/TLS → Origin Server
3. Create Certificate with:
   - Hostnames: `*.homelab.grenlan.com`, `homelab.grenlan.com`
   - Validity: 15 years
   - Key Type: RSA 2048

#### Phase 3: Deploy Certificate
```bash
# Run the setup script
cd ansible
./scripts/setup-cloudflare-ca.sh

# Or manually deploy using Ansible
ansible-playbook -i inventories/prod/hosts.yml playbooks/42-cloudflare-ca.yml
```

## Local DNS Configuration

### Option 1: Local DNS Server (Recommended)
Configure your router or local DNS server to resolve:
```
grafana.homelab.grenlan.com    → 192.168.1.11
prometheus.homelab.grenlan.com → 192.168.1.11
loki.homelab.grenlan.com       → 192.168.1.11
homelab.grenlan.com            → 192.168.1.11
```

### Option 2: Hosts File
Add to `/etc/hosts` (Linux/Mac) or `C:\Windows\System32\drivers\etc\hosts` (Windows):
```
192.168.1.11  homelab.grenlan.com
192.168.1.11  grafana.homelab.grenlan.com
192.168.1.11  prometheus.homelab.grenlan.com
192.168.1.11  loki.homelab.grenlan.com
```

## Caddy Configuration

### Secure Ingress with Local-Only Access
```caddyfile
# Only allow local network access
(internal_only) {
    @external {
        not remote_ip 192.168.1.0/24
        not remote_ip 10.0.0.0/8
        not remote_ip 172.16.0.0/12
        not remote_ip 127.0.0.1/32
    }
    respond @external "Access denied" 403
}

# Service configuration with Cloudflare certs
grafana.homelab.grenlan.com {
    import internal_only
    tls /etc/ssl/cloudflare/origin.crt /etc/ssl/cloudflare/origin.key
    reverse_proxy 192.168.1.12:3000
}
```

## Security Configuration

### 1. Network Security
- ✅ Services only accessible from local network (192.168.1.0/24)
- ✅ No public internet access (Cloudflare records unproxied)
- ✅ Firewall rules on each Pi restrict external access

### 2. Certificate Security
- ✅ 15-year validity eliminates renewal risks
- ✅ Cloudflare Origin CA provides strong encryption
- ✅ Private keys stored with 0600 permissions

### 3. Access Control
```bash
# UFW rules on pi-b (ingress)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.1.0/24 to any port 443
sudo ufw allow from 192.168.1.0/24 to any port 80
sudo ufw allow ssh
sudo ufw enable
```

## Automation & Lifecycle Management

### Certificate Monitoring
```bash
# Automated daily check via systemd timer
systemctl status cert-check.timer

# Manual check
/usr/local/bin/check-cert-expiry.sh
```

### Certificate Renewal Process
Although certificates are valid for 15 years, if renewal is needed:

1. Generate new certificate in Cloudflare Dashboard
2. Run deployment playbook:
   ```bash
   ansible-playbook -i inventories/prod/hosts.yml \
     playbooks/42-cloudflare-ca.yml \
     -e "cloudflare_origin_cert='<paste-cert-here>'"
   ```
3. Restart Caddy:
   ```bash
   ansible pi-b -i inventories/prod/hosts.yml -m systemd \
     -a "name=caddy state=restarted" --become
   ```

## Validation & Testing

### 1. DNS Resolution Test
```bash
# Should resolve to internal IP
dig +short grafana.homelab.grenlan.com
# Expected: 192.168.1.11 (or no result if using hosts file)

# From internal network
nslookup grafana.homelab.grenlan.com 192.168.1.1
```

### 2. Certificate Validation
```bash
# Check certificate
openssl s_client -connect grafana.homelab.grenlan.com:443 \
  -servername grafana.homelab.grenlan.com < /dev/null | \
  openssl x509 -noout -text | grep -A2 "Subject:"
```

### 3. Access Test
```bash
# From internal network (should work)
curl -k https://grafana.homelab.grenlan.com

# From external network (should fail)
# Test using mobile hotspot or VPN
```

## Service URLs

Once configured, access services at:

| Service | URL | Internal IP |
|---------|-----|-------------|
| Grafana | https://grafana.homelab.grenlan.com | 192.168.1.12:3000 |
| Prometheus | https://prometheus.homelab.grenlan.com | 192.168.1.12:9090 |
| Loki | https://loki.homelab.grenlan.com | 192.168.1.12:3100 |

## Troubleshooting

### Certificate Issues
```bash
# Check certificate validity
ansible pi-b -i inventories/prod/hosts.yml -m shell \
  -a "openssl x509 -in /etc/ssl/cloudflare/origin.crt -noout -dates"

# Check Caddy logs
ansible pi-b -i inventories/prod/hosts.yml -m shell \
  -a "sudo journalctl -u caddy -n 50"
```

### DNS Issues
```bash
# Flush DNS cache (Mac)
sudo dscacheutil -flushcache

# Flush DNS cache (Linux)
sudo systemd-resolve --flush-caches

# Flush DNS cache (Windows)
ipconfig /flushdns
```

### Access Issues
```bash
# Check firewall rules
ansible pi-b -i inventories/prod/hosts.yml -m shell \
  -a "sudo ufw status numbered"

# Check Caddy is listening
ansible pi-b -i inventories/prod/hosts.yml -m shell \
  -a "sudo ss -tlnp | grep :443"
```

## Benefits

1. **Security**: Services completely isolated from internet
2. **Simplicity**: 15-year certificates, no renewal hassle  
3. **Performance**: Direct local network access
4. **Reliability**: No dependency on internet for internal services
5. **Privacy**: Home network topology hidden from public

## Next Steps

1. [ ] Deploy Cloudflare Origin certificates to pi-b
2. [ ] Configure local DNS resolution
3. [ ] Update Caddy with new certificate paths
4. [ ] Test all service endpoints
5. [ ] Document in team wiki/runbook
6. [ ] Set up monitoring alerts for certificate expiry (14 years from now!)

---

*This configuration ensures your homelab services are secure, performant, and only accessible from your local network while leveraging Cloudflare's robust certificate infrastructure.*