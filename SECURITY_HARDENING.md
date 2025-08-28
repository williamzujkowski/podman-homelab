# Multi-Layer Security Architecture for Pi Cluster

## Current Security Layers

### Layer 1: Reverse Proxy (Traefik) ✅
- **Purpose**: Single entry point, hides internal services
- **Currently**: Basic reverse proxy with TLS
- **Needs**: Additional security middlewares

### Layer 2: Network Security 🔧
- **Purpose**: Minimize attack surface
- **Currently**: Direct port forwarding
- **Needs**: DMZ, VLANs, or Cloudflare Tunnel

### Layer 3: Authentication & Authorization 🔧
- **Purpose**: Control access
- **Currently**: Basic service passwords
- **Needs**: Centralized auth, 2FA, OAuth2

## Enhanced Security Architecture

```
Internet
    ↓
[Cloudflare CDN/WAF] (Optional but recommended)
    ↓
[Your Router/Firewall]
    ↓
[Fail2ban + UFW on pi-b]
    ↓
[Traefik Reverse Proxy on pi-b]
    - Rate Limiting
    - GeoIP Blocking
    - Security Headers
    - WAF Rules
    - OAuth2/Authelia
    ↓
[Internal Services on pi-a, pi-c, pi-d]
    - No direct internet access
    - Internal network only
```

## Security Enhancements to Implement

### 1. Cloudflare Proxy (Highly Recommended) 🛡️

**Benefits:**
- Hides your home IP address
- DDoS protection
- WAF (Web Application Firewall)
- Bot protection
- Caching
- Zero Trust Access

**Setup:**
```bash
# In Cloudflare Dashboard:
# 1. Add your domain
# 2. Enable "Proxied" (orange cloud) for all records
# 3. Set Security Level to "High"
# 4. Enable "Bot Fight Mode"
# 5. Setup Page Rules for additional security

# DNS Records (Cloudflare proxied):
A    homelab     YOUR_IP    Proxied ✓
A    *.homelab   YOUR_IP    Proxied ✓
```

### 2. Authelia (Single Sign-On + 2FA) 🔐

**Deploy Authelia for centralized authentication:**

```yaml
# /home/william/git/podman-homelab/authelia/configuration.yml
---
theme: dark
jwt_secret: "YOUR_JWT_SECRET_HERE"  # Generate with: openssl rand -hex 32
default_redirection_url: https://homelab.grenlan.com

server:
  host: 0.0.0.0
  port: 9091

log:
  level: info

totp:
  issuer: grenlan.com
  period: 30
  skew: 1

authentication_backend:
  file:
    path: /config/users_database.yml
    password:
      algorithm: argon2id
      iterations: 1
      key_length: 32
      salt_length: 16
      memory: 512
      parallelism: 8

access_control:
  default_policy: deny
  rules:
    # Public access
    - domain: "homelab.grenlan.com"
      policy: bypass
    
    # 2FA required for admin services
    - domain: 
        - "prometheus.homelab.grenlan.com"
        - "traefik.homelab.grenlan.com"
      policy: two_factor
    
    # Single factor for user services
    - domain: "grafana.homelab.grenlan.com"
      policy: one_factor

session:
  name: authelia_session
  secret: "YOUR_SESSION_SECRET_HERE"  # Generate with: openssl rand -hex 32
  expiration: 1h
  inactivity: 15m
  remember_me_duration: 1M
  domain: grenlan.com

regulation:
  max_retries: 3
  find_time: 2m
  ban_time: 5m

storage:
  local:
    path: /config/db.sqlite3

notifier:
  filesystem:
    filename: /config/notification.txt
```

**Deploy Authelia container:**
```bash
# On pi-b (ingress node)
podman run -d --name authelia \
  --restart always \
  -p 9091:9091 \
  -v /etc/authelia:/config:Z \
  -e TZ=America/New_York \
  docker.io/authelia/authelia:latest
```

### 3. Fail2ban + GeoIP Blocking 🚫

```bash
# Install fail2ban on pi-b
ssh pi@192.168.1.11 << 'EOF'
sudo apt-get install -y fail2ban geoip-bin geoip-database

# Create Traefik jail
sudo cat > /etc/fail2ban/jail.d/traefik.conf << 'CONFIG'
[traefik-auth]
enabled = true
port = http,https
filter = traefik-auth
logpath = /var/log/traefik/access.log
maxretry = 5
bantime = 3600
findtime = 600

[traefik-ratelimit]
enabled = true
port = http,https
filter = traefik-ratelimit
logpath = /var/log/traefik/access.log
maxretry = 100
bantime = 600
findtime = 60
CONFIG

# Create filter rules
sudo cat > /etc/fail2ban/filter.d/traefik-auth.conf << 'FILTER'
[Definition]
failregex = ^<HOST> - - \[.*\] ".*" 401 .*$
ignoreregex =
FILTER

sudo systemctl restart fail2ban
EOF
```

### 4. Network Segmentation (VLANs) 🔒

```yaml
# Recommended VLAN setup:
VLAN 10: Management (Your admin devices)
VLAN 20: DMZ (pi-b only - exposed to internet)
VLAN 30: Services (pi-a, pi-c, pi-d - internal only)
VLAN 40: IoT (Other devices, if any)

# Firewall rules:
DMZ → Services: Allow specific ports only
Services → Internet: Deny (except updates)
Management → All: Allow
Internet → DMZ: Only 80,443
```

### 5. Crowdsec (Community-based IPS) 🛡️

```bash
# Install CrowdSec on pi-b
curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | sudo bash
sudo apt-get install crowdsec crowdsec-firewall-bouncer-iptables

# Install Traefik bouncer
sudo crowdsec-bouncer-install traefik

# Configure for Traefik
sudo cscli parsers install crowdsecurity/traefik-logs
sudo cscli scenarios install crowdsecurity/http-probing
sudo systemctl restart crowdsec
```

### 6. Enhanced Traefik Security Configuration 🔧

```yaml
# /etc/traefik/dynamic/security-enhanced.yml
http:
  middlewares:
    # Authelia authentication
    authelia:
      forwardAuth:
        address: "http://localhost:9091/api/verify?rd=https://authelia.homelab.grenlan.com"
        trustForwardHeader: true
        authResponseHeaders:
          - Remote-User
          - Remote-Groups
          - Remote-Name
          - Remote-Email
    
    # Rate limiting per IP
    rate-limit-strict:
      rateLimit:
        average: 10
        burst: 20
        period: 1m
        sourceCriterion:
          ipStrategy:
            depth: 2
            excludedIPs:
              - "192.168.1.0/24"  # Don't limit internal network
    
    # GeoIP blocking
    geoblock:
      plugin:
        geoblock:
          silentStartUp: false
          allowLocalRequests: true
          logLocalRequests: false
          logAllowedRequests: false
          logApiRequests: false
          allowUnknownCountries: false
          unknownCountryApiResponse: "nil"
          blackListMode: false
          countries:
            - US  # Allow US
            - CA  # Allow Canada
            # Add your country
    
    # Security headers enhanced
    security-headers-strict:
      headers:
        customRequestHeaders:
          X-Real-IP: ""  # Remove real IP from headers
        frameDeny: true
        sslRedirect: true
        browserXssFilter: true
        contentTypeNosniff: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 63072000  # 2 years
        customFrameOptionsValue: "DENY"
        contentSecurityPolicy: "default-src 'self'"
        permissionsPolicy: "geolocation=(), microphone=(), camera=()"
        customResponseHeaders:
          X-Robots-Tag: "noindex,nofollow,noarchive"
          Server: ""
          X-Powered-By: ""
    
    # IP whitelist for admin services
    ip-whitelist:
      ipWhiteList:
        sourceRange:
          - "192.168.1.0/24"  # Internal network
          - "YOUR_HOME_IP/32"  # Your home IP (if static)
          # Add trusted IPs only
```

### 7. Cloudflare Tunnel (Alternative - No Port Forwarding) 🚇

```bash
# Install cloudflared on pi-b
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 \
  -o cloudflared
sudo mv cloudflared /usr/local/bin/
sudo chmod +x /usr/local/bin/cloudflared

# Login to Cloudflare
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create pi-cluster

# Create config
cat > ~/.cloudflared/config.yml << 'EOF'
tunnel: YOUR_TUNNEL_ID
credentials-file: /home/pi/.cloudflared/YOUR_TUNNEL_ID.json

ingress:
  - hostname: grafana.homelab.grenlan.com
    service: http://localhost:80
    originRequest:
      noTLSVerify: true
      httpHostHeader: grafana.homelab.grenlan.com
  
  - hostname: prometheus.homelab.grenlan.com
    service: http://localhost:80
    originRequest:
      httpHostHeader: prometheus.homelab.grenlan.com
  
  - service: http_status:404
EOF

# Run as service
sudo cloudflared service install
sudo systemctl start cloudflared
```

### 8. Container Security Hardening 🐳

```yaml
# Podman security options for all containers
podman run -d \
  --name service \
  --read-only \                    # Read-only root filesystem
  --tmpfs /tmp \                    # Temporary filesystem for /tmp
  --cap-drop=ALL \                  # Drop all capabilities
  --cap-add=NET_BIND_SERVICE \     # Add only needed capabilities
  --security-opt=no-new-privileges \ # No privilege escalation
  --cpus="0.5" \                   # Limit CPU
  --memory="512m" \                 # Limit memory
  --restart=on-failure:5 \          # Limited restart attempts
  image:tag
```

### 9. Monitoring & Alerting 📊

```yaml
# Deploy Grafana Loki for centralized logging
podman run -d --name loki \
  -p 3100:3100 \
  -v /etc/loki:/etc/loki:Z \
  grafana/loki:latest \
  -config.file=/etc/loki/loki-config.yaml

# Deploy Promtail on all nodes
podman run -d --name promtail \
  -v /var/log:/var/log:ro \
  -v /etc/promtail:/etc/promtail:Z \
  grafana/promtail:latest \
  -config.file=/etc/promtail/config.yml

# Alert rules for security events
# - Failed authentication attempts > 5 in 5 minutes
# - Unusual traffic patterns
# - Service health issues
# - Certificate expiration < 7 days
```

### 10. Regular Security Tasks 📅

```bash
# Create security maintenance script
cat > /home/pi/security-maintenance.sh << 'EOF'
#!/bin/bash
# Weekly security tasks

# Update fail2ban
sudo fail2ban-client status

# Check for updates
sudo apt update && sudo apt list --upgradable

# Review auth logs
echo "=== Recent Auth Failures ==="
sudo grep "authentication failure" /var/log/auth.log | tail -20

# Check certificate expiry
echo "=== Certificate Status ==="
echo | openssl s_client -servername homelab.grenlan.com \
  -connect homelab.grenlan.com:443 2>/dev/null | \
  openssl x509 -noout -dates

# Review Traefik access logs for suspicious activity
echo "=== Suspicious Activity ==="
sudo grep -E "40[0-9]|50[0-9]" /var/log/traefik/access.log | \
  awk '{print $1}' | sort | uniq -c | sort -rn | head -10

# Check disk usage
echo "=== Disk Usage ==="
df -h

# Backup critical configs
sudo tar czf /storage/backups/security-config-$(date +%Y%m%d).tar.gz \
  /etc/traefik /etc/authelia /etc/fail2ban
EOF

chmod +x /home/pi/security-maintenance.sh

# Add to crontab
(crontab -l; echo "0 2 * * 0 /home/pi/security-maintenance.sh") | crontab -
```

## Security Implementation Priority

### Phase 1: Essential (Do First)
1. ✅ Traefik reverse proxy (already done)
2. ⏳ Cloudflare proxy (hides IP, adds WAF)
3. ⏳ Fail2ban (blocks attackers)
4. ⏳ Enhanced security headers

### Phase 2: Important (Do Soon)
5. ⏳ Authelia (SSO + 2FA)
6. ⏳ Network segmentation (VLANs)
7. ⏳ CrowdSec (community IPS)
8. ⏳ Monitoring & alerting

### Phase 3: Nice to Have
9. ⏳ Cloudflare Tunnel (alternative to port forwarding)
10. ⏳ Container hardening
11. ⏳ Regular security audits

## Security Checklist

- [ ] Never expose services directly to internet
- [ ] Use Cloudflare proxy to hide home IP
- [ ] Enable 2FA on all admin interfaces
- [ ] Implement rate limiting
- [ ] Set up fail2ban
- [ ] Use strong, unique passwords
- [ ] Monitor logs regularly
- [ ] Keep everything updated
- [ ] Backup configurations
- [ ] Test disaster recovery
- [ ] Document everything
- [ ] Use VLANs to segment network
- [ ] Implement least privilege principle
- [ ] Regular security audits
- [ ] Certificate monitoring

## Testing Security

```bash
# Test from external network (use mobile data)
# 1. Port scan (should only see 80,443)
nmap -Pn homelab.grenlan.com

# 2. SSL test
https://www.ssllabs.com/ssltest/analyze.html?d=homelab.grenlan.com

# 3. Security headers test
https://securityheaders.com/?q=homelab.grenlan.com

# 4. Try common attacks (from external IP)
# - Brute force (should get banned)
# - SQL injection attempts (should be blocked)
# - Directory traversal (should be blocked)
```

## Emergency Response Plan

### If Compromised:
1. **Immediate**: Disable port forwarding at router
2. **Isolate**: Disconnect affected Pi from network
3. **Investigate**: Check logs for entry point
4. **Clean**: Reinstall OS from backup
5. **Harden**: Implement missed security measures
6. **Monitor**: Watch closely for 30 days

### Backup Strategy:
- Configuration backups: Daily to /storage
- Full system backups: Weekly to external drive
- Test restore: Monthly verification
- Offsite backup: Critical configs to encrypted cloud

## Cost-Benefit Analysis

| Security Measure | Cost | Benefit | Priority |
|-----------------|------|---------|----------|
| Cloudflare Proxy | Free | Hides IP, DDoS protection | HIGH |
| Fail2ban | Free | Blocks attackers | HIGH |
| Authelia + 2FA | Free | Strong authentication | HIGH |
| VLANs | Time | Network isolation | MEDIUM |
| CrowdSec | Free | Community protection | MEDIUM |
| Cloudflare Tunnel | Free | No port forwarding | LOW |
| Commercial WAF | $$$ | Advanced protection | LOW |