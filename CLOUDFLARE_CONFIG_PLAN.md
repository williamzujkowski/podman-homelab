# Cloudflare Configuration Plan for grenlan.com

## Overview
This document outlines the complete Cloudflare configuration for your homelab using the MCP server.

## Phase 1: DNS Cleanup & Setup

### Records to Remove (cPanel cruft)
- autodiscover.grenlan.com
- cpanel.grenlan.com  
- cpcalendars.grenlan.com
- cpcontacts.grenlan.com
- webdisk.grenlan.com
- webmail.grenlan.com
- All mail-related records (MX, mail.grenlan.com)
- ftp.grenlan.com
- whm.grenlan.com

### Records to Add
```
A    homelab           100.36.107.208   Proxied ✓
A    *.homelab         100.36.107.208   Proxied ✓
CAA  grenlan.com       0 issue "letsencrypt.org"
CAA  grenlan.com       0 issue "pki.goog"
CAA  grenlan.com       0 issue "digicert.com"
```

## Phase 2: SSL/TLS Configuration

### Cloudflare Origin Certificate Setup
1. Generate 15-year Origin Certificate for:
   - `*.grenlan.com`
   - `grenlan.com`  
   - `*.homelab.grenlan.com`
   - `homelab.grenlan.com`

2. Deploy certificate to Traefik on pi-b (192.168.1.11)

### SSL/TLS Settings
- Mode: Full (strict)
- Always Use HTTPS: ON
- Automatic HTTPS Rewrites: ON
- Minimum TLS Version: 1.2
- Opportunistic Encryption: ON
- TLS 1.3: ON

## Phase 3: Security Configuration

### Firewall Rules to Create

1. **Block High Threat Score**
   ```
   Expression: (cf.threat_score gt 30)
   Action: Challenge
   Priority: 1
   ```

2. **Rate Limiting**
   ```
   Expression: (http.request.uri.path contains "/api/" and rate() > 100)
   Action: Challenge  
   Priority: 2
   ```

3. **Block Bad Bots**
   ```
   Expression: (cf.bot_score lt 30)
   Action: Block
   Priority: 3
   ```

4. **Geographic Restrictions (optional)**
   ```
   Expression: (ip.geoip.country in {"CN" "RU" "KP"})
   Action: Challenge
   Priority: 4
   ```

### Security Settings
- Security Level: High
- Challenge Passage: 30 minutes
- Browser Integrity Check: ON
- Privacy Pass Support: ON
- Always Online: ON

### Bot Management
- Bot Fight Mode: ON
- Verified Bot Access: Allow
- JavaScript Detection: ON

### DDoS Protection
- DDoS Protection: ON (automatic with proxy)
- Rate Limiting: Configured via firewall rules

## Phase 4: Performance Settings

### Caching
- Caching Level: Standard
- Browser Cache TTL: 4 hours
- Always Online: ON
- Development Mode: OFF (toggle as needed)

### Speed Optimizations
- Auto Minify: JavaScript, CSS, HTML
- Brotli: ON
- HTTP/2: ON
- HTTP/3 (with QUIC): ON
- 0-RTT Connection Resumption: ON

## Phase 5: Service-Specific Configuration

### Service URLs (all proxied through Cloudflare)
- https://grafana.homelab.grenlan.com → pi-c:3000
- https://prometheus.homelab.grenlan.com → pi-c:9090  
- https://traefik.homelab.grenlan.com → pi-b:8080
- https://minio.homelab.grenlan.com → pi-d:9001

### Page Rules (optional enhancements)
1. `*homelab.grenlan.com/api/*`
   - Cache Level: Bypass
   - Security Level: High

2. `*homelab.grenlan.com/static/*`
   - Cache Level: Cache Everything
   - Edge Cache TTL: 1 month

## Phase 6: Monitoring & Maintenance

### Analytics to Monitor
- Traffic patterns
- Threat events
- Cache hit ratio
- Origin response times

### Regular Tasks
- Review firewall event logs
- Check SSL certificate status
- Monitor bot traffic
- Review security events

## Implementation Commands

Once MCP server is connected, these commands will be executed:

```javascript
// 1. Clean up DNS records
await mcp.delete_dns_record({domain: "grenlan.com", record_id: "autodiscover_id"});
await mcp.delete_dns_record({domain: "grenlan.com", record_id: "cpanel_id"});
// ... etc for all cleanup records

// 2. Add homelab records
await mcp.create_dns_record({
  domain: "grenlan.com",
  type: "A",
  name: "homelab",
  content: "100.36.107.208",
  proxied: true
});

await mcp.create_dns_record({
  domain: "grenlan.com",
  type: "A", 
  name: "*.homelab",
  content: "100.36.107.208",
  proxied: true
});

// 3. Configure SSL
await mcp.update_ssl_mode({
  domain: "grenlan.com",
  mode: "full"
});

// 4. Create firewall rules
await mcp.create_firewall_rule({
  domain: "grenlan.com",
  expression: "cf.threat_score gt 30",
  action: "challenge",
  description: "Challenge high threat scores",
  priority: 1
});

// 5. Update security settings
await mcp.update_zone_setting({
  domain: "grenlan.com",
  setting_name: "security_level",
  value: "high"
});
```

## Validation Tests

1. **DNS Resolution**
   ```bash
   dig +short homelab.grenlan.com
   dig +short grafana.homelab.grenlan.com
   ```

2. **SSL Certificate Check**
   ```bash
   openssl s_client -connect homelab.grenlan.com:443 -servername homelab.grenlan.com
   ```

3. **Security Headers**
   ```bash
   curl -I https://homelab.grenlan.com
   ```

4. **Service Access**
   - https://grafana.homelab.grenlan.com (should load)
   - https://prometheus.homelab.grenlan.com (should require auth)
   - https://traefik.homelab.grenlan.com (should require auth)

## Rollback Plan

If issues occur:
1. Disable Cloudflare proxy (grey cloud) for immediate bypass
2. Revert SSL mode to Flexible if certificate issues
3. Disable firewall rules if blocking legitimate traffic
4. Use Development Mode to bypass cache during troubleshooting

## Benefits Once Configured

✅ **Security**: Home IP hidden, DDoS protection, WAF, bot protection
✅ **Performance**: Global CDN, caching, HTTP/3, Brotli compression
✅ **Reliability**: Always Online, automatic failover
✅ **Simplicity**: 15-year certificates, no renewal needed
✅ **Monitoring**: Real-time analytics and threat detection