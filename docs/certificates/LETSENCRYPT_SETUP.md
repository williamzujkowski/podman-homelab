# Let's Encrypt Certificate Setup for grenlan.com

## Current Status
- **Domain**: grenlan.com (owned and controlled via cPanel)
- **Public IP**: 100.36.107.208
- **Current DNS**: grenlan.com points to 104.225.208.28 (needs updating)
- **Cluster Ingress**: pi-b (192.168.1.11) - Traefik

## Step 1: DNS Configuration in cPanel

Add these DNS records in your cPanel Zone Editor:

### Option A: Direct to Home IP (Simple but exposes home IP)
```
Type  Name                    Content           TTL
A     pi                      100.36.107.208    300
A     *.pi                    100.36.107.208    300
A     grafana                 100.36.107.208    300
A     prometheus              100.36.107.208    300
A     traefik                 100.36.107.208    300
A     minio                   100.36.107.208    300
```

### Option B: Using Subdomains Only (More secure, doesn't affect main domain)
```
Type  Name                    Content           TTL
A     homelab                 100.36.107.208    300
A     *.homelab              100.36.107.208    300
CNAME grafana.pi             homelab.grenlan.com
CNAME prometheus.pi          homelab.grenlan.com
CNAME traefik.pi            homelab.grenlan.com
CNAME minio.pi              homelab.grenlan.com
```

**Recommendation**: Use Option B to keep your main domain separate from your homelab.

## Step 2: Firewall Configuration

### Secure Port Forwarding Rules

Configure your router/firewall with these **restricted** rules:

```
# Minimal exposure - only what's needed for Let's Encrypt
External Port 80  -> Internal 192.168.1.11:80  (TCP)
External Port 443 -> Internal 192.168.1.11:443 (TCP)

# Optional: Restrict source IPs to Let's Encrypt validation servers
# Let's Encrypt doesn't publish fixed IPs, so this isn't practical
```

### Firewall Security Hardening

1. **Enable DDoS Protection** if available
2. **Rate Limiting**: Max 10 connections per second per IP on port 80/443
3. **Geo-blocking**: Consider blocking countries you don't expect traffic from
4. **IDS/IPS**: Enable if available on your firewall

## Step 3: Traefik Configuration with Let's Encrypt

### Create Traefik configuration with security headers:

```yaml
# /etc/traefik/traefik.yml
api:
  dashboard: true
  # Disable insecure API access
  insecure: false

entryPoints:
  web:
    address: ":80"
    # Rate limiting on HTTP endpoint
    http:
      middlewares:
        - rate-limit@file
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  
  websecure:
    address: ":443"
    http:
      middlewares:
        - security-headers@file
        - rate-limit@file

certificatesResolvers:
  letsencrypt:
    acme:
      email: YOUR_EMAIL@example.com  # CHANGE THIS
      storage: /etc/traefik/acme.json
      keyType: EC256  # Use elliptic curve for better security
      # Start with staging
      caServer: https://acme-staging-v02.api.letsencrypt.org/directory
      httpChallenge:
        entryPoint: web

providers:
  docker:
    endpoint: "unix:///run/podman/podman.sock"
    exposedByDefault: false
  file:
    directory: /etc/traefik/dynamic
    watch: true

log:
  level: INFO
  filePath: /var/log/traefik/traefik.log

accessLog:
  filePath: /var/log/traefik/access.log
  filters:
    statusCodes:
      - "400-499"
      - "500-599"

# Global security settings
serversTransport:
  insecureSkipVerify: false
  maxIdleConnsPerHost: 7
```

### Security Middleware Configuration:

```yaml
# /etc/traefik/dynamic/security.yml
http:
  middlewares:
    security-headers:
      headers:
        frameDeny: true
        sslRedirect: true
        browserXssFilter: true
        contentTypeNosniff: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 31536000
        customFrameOptionsValue: "SAMEORIGIN"
        customResponseHeaders:
          X-Robots-Tag: "noindex,nofollow,noarchive"
          Server: ""  # Hide server version
    
    rate-limit:
      rateLimit:
        average: 100
        burst: 50
        period: 1m
        
    basic-auth:
      basicAuth:
        users:
          # Generate with: htpasswd -nb admin your-password
          # Default: admin/picluster (CHANGE THIS!)
          - "admin:$2y$10$YourHashedPasswordHere"
```

### Service Routes with Domain Validation:

```yaml
# /etc/traefik/dynamic/routes.yml
http:
  routers:
    grafana:
      rule: "Host(`grafana.pi.grenlan.com`)"
      service: grafana
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt
        domains:
          - main: "grafana.pi.grenlan.com"
    
    prometheus:
      rule: "Host(`prometheus.pi.grenlan.com`)"
      service: prometheus
      entryPoints:
        - websecure
      middlewares:
        - basic-auth  # Add authentication
      tls:
        certResolver: letsencrypt
    
    traefik-dashboard:
      rule: "Host(`traefik.pi.grenlan.com`) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))"
      service: api@internal
      entryPoints:
        - websecure
      middlewares:
        - basic-auth
      tls:
        certResolver: letsencrypt
    
    minio:
      rule: "Host(`minio.pi.grenlan.com`)"
      service: minio
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

  services:
    grafana:
      loadBalancer:
        servers:
          - url: "http://192.168.1.12:3000"
        healthCheck:
          path: /api/health
          interval: 30s
          timeout: 3s
    
    prometheus:
      loadBalancer:
        servers:
          - url: "http://192.168.1.12:9090"
        healthCheck:
          path: /-/healthy
          interval: 30s
          timeout: 3s
    
    minio:
      loadBalancer:
        servers:
          - url: "http://192.168.1.13:9001"
```

## Step 4: Deployment Steps

### 1. First, verify DNS propagation:
```bash
# Wait for DNS to propagate (5-30 minutes after adding records)
nslookup grafana.pi.grenlan.com 8.8.8.8
# Should return your public IP: 100.36.107.208
```

### 2. Deploy configuration to Traefik:
```bash
# Create log directory
ssh pi@192.168.1.11 "sudo mkdir -p /var/log/traefik"

# Deploy configurations
scp traefik.yml pi@192.168.1.11:/tmp/
scp security.yml pi@192.168.1.11:/tmp/
scp routes.yml pi@192.168.1.11:/tmp/

ssh pi@192.168.1.11 "
  sudo cp /tmp/traefik.yml /etc/traefik/
  sudo cp /tmp/security.yml /etc/traefik/dynamic/
  sudo cp /tmp/routes.yml /etc/traefik/dynamic/
  sudo touch /etc/traefik/acme.json
  sudo chmod 600 /etc/traefik/acme.json
"

# Restart Traefik
ssh pi@192.168.1.11 "podman restart traefik"
```

### 3. Test with Let's Encrypt Staging:
```bash
# Monitor Traefik logs
ssh pi@192.168.1.11 "podman logs -f traefik"

# In another terminal, test certificate generation
curl -I https://grafana.pi.grenlan.com
# Will show certificate error (staging cert not trusted) - this is expected
```

### 4. Switch to Production (after staging works):
```bash
# Edit traefik.yml and comment out the caServer line:
# caServer: https://acme-staging-v02.api.letsencrypt.org/directory

# Remove staging certificates
ssh pi@192.168.1.11 "sudo rm /etc/traefik/acme.json && sudo touch /etc/traefik/acme.json && sudo chmod 600 /etc/traefik/acme.json"

# Restart Traefik
ssh pi@192.168.1.11 "podman restart traefik"
```

## Step 5: Security Verification

### Test SSL Configuration:
```bash
# Check SSL Labs score (wait 5 minutes after cert generation)
# Visit: https://www.ssllabs.com/ssltest/analyze.html?d=grafana.pi.grenlan.com

# Test locally
openssl s_client -connect grafana.pi.grenlan.com:443 -servername grafana.pi.grenlan.com

# Verify certificate details
curl -vI https://grafana.pi.grenlan.com 2>&1 | grep -A 5 "SSL certificate"
```

### Monitor for Issues:
```bash
# Check Traefik logs for errors
ssh pi@192.168.1.11 "grep ERROR /var/log/traefik/traefik.log"

# Monitor access attempts
ssh pi@192.168.1.11 "tail -f /var/log/traefik/access.log | grep -v 200"
```

## Step 6: Automatic Renewal

Traefik handles renewal automatically, but monitor it:

```bash
# Create monitoring script
cat > /home/pi/check-certs.sh << 'EOF'
#!/bin/bash
DOMAINS="grafana.pi.grenlan.com prometheus.pi.grenlan.com"
for domain in $DOMAINS; do
  echo -n "$domain: "
  echo | openssl s_client -servername $domain -connect $domain:443 2>/dev/null | \
    openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2
done
EOF

# Add to crontab (weekly check)
(crontab -l 2>/dev/null; echo "0 9 * * 1 /home/pi/check-certs.sh") | crontab -
```

## Security Best Practices

1. **Never expose internal services directly**
   - Always proxy through Traefik
   - Use authentication middleware

2. **Monitor logs regularly**
   - Set up alerts for 4xx/5xx errors
   - Watch for scanning attempts

3. **Keep services updated**
   - Regular Traefik updates
   - Security patches for all services

4. **Backup certificates**
   ```bash
   ssh pi@192.168.1.11 "sudo cp /etc/traefik/acme.json /storage/backups/acme-$(date +%Y%m%d).json"
   ```

5. **Use strong passwords**
   - Change all default passwords
   - Use different passwords for each service

## Troubleshooting

### DNS Issues
```bash
# Check DNS propagation
dig +short grafana.pi.grenlan.com @8.8.8.8
dig +short grafana.pi.grenlan.com @1.1.1.1

# Should return your public IP
```

### Certificate Generation Issues
```bash
# Check ACME challenges
ssh pi@192.168.1.11 "podman logs traefik | grep -i acme"

# Verify port 80 is accessible
curl -I http://grafana.pi.grenlan.com
```

### Rate Limit Issues
- Let's Encrypt allows 50 certs per week per domain
- Use staging for testing
- Check current rate limit: https://crt.sh/?q=grenlan.com

## Alternative: DNS-01 Challenge (No Open Ports)

If you prefer not to open any ports, you can use DNS-01 challenge with cPanel API:

```yaml
# Requires cPanel API credentials
certificatesResolvers:
  letsencrypt:
    acme:
      email: your-email@example.com
      storage: /etc/traefik/acme.json
      dnsChallenge:
        provider: manual  # Or use a provider that supports cPanel
        delayBeforeCheck: 60
```

This requires manual DNS record creation for each renewal, or automation via cPanel API.