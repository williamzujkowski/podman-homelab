# Homelab Infrastructure - Complete Access Guide

**Last Updated:** 2025-08-28  
**Status:** ✅ Monitoring Stack Operational

## Quick Access Summary

### 🟢 Working Access Methods

#### Direct HTTP Access (Currently Working)
Access services directly via HTTP from your local network:

| Service | Direct URL | Status | Purpose |
|---------|-----------|--------|---------|
| **Grafana** | http://192.168.1.12:3000 | ✅ Working | Dashboards & Visualization |
| **Prometheus** | http://192.168.1.12:9090 | ✅ Working | Metrics Database |
| **Loki** | http://192.168.1.12:3100 | ✅ Working | Log Aggregation |
| **Node Exporter** | http://192.168.1.12:9100 | ✅ Working | System Metrics |

#### SSH Tunnel Access (Secure Alternative)
For secure remote access, use SSH tunneling:

```bash
# Create SSH tunnel to access all services securely
ssh -L 3000:localhost:3000 \
    -L 9090:localhost:9090 \
    -L 3100:localhost:3100 \
    pi@192.168.1.12

# Then access locally:
# Grafana: http://localhost:3000
# Prometheus: http://localhost:9090
# Loki: http://localhost:3100
```

### 🟢 HTTPS Access (Browser-Trusted!)

| Service | HTTPS URL | Status | Notes |
|---------|-----------|--------|-------|
| Grafana | https://grafana.homelab.grenlan.com | ✅ Working | Let's Encrypt Certificate |
| Prometheus | https://prometheus.homelab.grenlan.com | ✅ Working | Let's Encrypt Certificate |
| Loki | https://loki.homelab.grenlan.com | ⚠️ Service Down | Needs restart |
| Homelab | https://homelab.grenlan.com | ✅ Working | Let's Encrypt Certificate |

**Note:** Let's Encrypt certificates are active! Browser-trusted TLS with auto-renewal every 60 days.

## Infrastructure Overview

### Network Topology

```
Your Computer
     |
     ├── Direct HTTP ──→ 192.168.1.12 (pi-a) ──→ Services
     |
     ├── DNS (UDM Pro) ──→ *.homelab.grenlan.com → 192.168.1.11
     |
     └── HTTPS (Future) ──→ 192.168.1.11 (pi-b/Traefik) ──→ 192.168.1.12 (Services)
```

### Node Configuration

| Node | IP | Hostname | Role | Services |
|------|-----|----------|------|----------|
| **pi-a** | 192.168.1.12 | pi-a.grenlan.com | Monitoring | Grafana, Prometheus, Loki, Node Exporter |
| **pi-b** | 192.168.1.11 | pi-b.grenlan.com | Ingress | Traefik (Reverse Proxy) |
| **pi-c** | 192.168.1.10 | pi-c.grenlan.com | Worker | (Ready for apps) |
| **pi-d** | 192.168.1.13 | pi-d.grenlan.com | Storage | (Ready for MinIO) |

## Service Details

### Grafana (Port 3000)
- **URL:** http://192.168.1.12:3000
- **Default Login:** admin/admin (change on first login)
- **Purpose:** Visualization dashboards for metrics and logs
- **Data Sources:** 
  - Prometheus (metrics)
  - Loki (logs)

### Prometheus (Port 9090)
- **URL:** http://192.168.1.12:9090
- **Purpose:** Time-series metrics database
- **Targets:** http://192.168.1.12:9090/targets
- **Configuration:** Native systemd service

### Loki (Port 3100)
- **URL:** http://192.168.1.12:3100
- **Purpose:** Log aggregation system
- **Ready Check:** http://192.168.1.12:3100/ready
- **Configuration:** Podman Quadlet container

### Node Exporter (Port 9100)
- **URL:** http://192.168.1.12:9100/metrics
- **Purpose:** System and hardware metrics
- **Metrics:** CPU, memory, disk, network statistics

## Access Methods by Location

### From Home Network
1. **Direct HTTP** - Use the direct URLs above
2. **DNS Names** - Configure your `/etc/hosts`:
   ```bash
   # Add to /etc/hosts
   192.168.1.12  pi-a.grenlan.com
   192.168.1.11  pi-b.grenlan.com homelab.grenlan.com
   192.168.1.11  grafana.homelab.grenlan.com
   192.168.1.11  prometheus.homelab.grenlan.com
   192.168.1.11  loki.homelab.grenlan.com
   ```

### From Remote Location
Use SSH tunneling for secure access:
```bash
# Single service tunnel
ssh -L 3000:localhost:3000 pi@192.168.1.12
# Access at: http://localhost:3000

# Multiple service tunnel
ssh -L 3000:localhost:3000 \
    -L 9090:localhost:9090 \
    -L 3100:localhost:3100 \
    pi@192.168.1.12
```

## Troubleshooting

### Cannot Access Services?

1. **Check Service Status:**
   ```bash
   ssh pi@192.168.1.12 "systemctl status grafana-server prometheus"
   ssh pi@192.168.1.12 "podman ps | grep loki"
   ```

2. **Check Network Connectivity:**
   ```bash
   ping 192.168.1.12  # Should respond
   nc -zv 192.168.1.12 3000  # Should show "succeeded"
   ```

3. **Check DNS Resolution:**
   ```bash
   dig grafana.homelab.grenlan.com  # Should return 192.168.1.11
   dig @192.168.1.1 grafana.homelab.grenlan.com  # Query UDM Pro
   ```

### HTTPS with Let's Encrypt!
Browser-trusted certificates via certbot with Cloudflare DNS-01 challenge.

**Current Status:**
- ✅ Let's Encrypt certificates generated via DNS-01 challenge
- ✅ Certificates deployed to `/etc/letsencrypt/live/homelab.grenlan.com/`
- ✅ Traefik configured to use certbot certificates
- ✅ Auto-renewal configured (systemd timer twice daily)
- ✅ Browser-trusted HTTPS access working!

## Security Notes

1. **All services are internal only** - Not accessible from the internet
2. **Cloudflare DNS is proxied** - Public DNS doesn't reveal internal IPs
3. **Let's Encrypt certificates** - Valid for 90 days with auto-renewal
4. **Use SSH tunneling for remote access** - Most secure method

## Certificate Management

### Check Certificate Status
```bash
ssh pi@192.168.1.11 "sudo /opt/certbot-env/bin/certbot certificates"
```

### Test Certificate Renewal
```bash
ssh pi@192.168.1.11 "sudo /opt/certbot-env/bin/certbot renew --dry-run"
```

### View Auto-Renewal Timer
```bash
ssh pi@192.168.1.11 "sudo systemctl status certbot-renew.timer"
```

### Manual Certificate Update to Traefik
```bash
ssh pi@192.168.1.11 "sudo cp /etc/letsencrypt/live/homelab.grenlan.com/*.pem /etc/traefik/certs/ && podman restart systemd-traefik"
```

## Common Tasks

### View Grafana Dashboards
1. Access: http://192.168.1.12:3000
2. Login with admin/admin (first time)
3. Add data sources:
   - Prometheus: http://localhost:9090
   - Loki: http://localhost:3100

### Query Metrics in Prometheus
1. Access: http://192.168.1.12:9090
2. Example queries:
   - `up` - Show which targets are up
   - `node_cpu_seconds_total` - CPU usage
   - `node_memory_MemAvailable_bytes` - Available memory

### View Logs in Loki
1. Access via Grafana's Explore page
2. Select Loki data source
3. Query examples:
   - `{job="node"}` - Node logs
   - `{container="grafana"}` - Container logs

## Next Steps

### Immediate (You can do now):
- ✅ Access all monitoring services via HTTP
- ✅ Configure Grafana dashboards
- ✅ Set up Prometheus scrape targets
- ✅ Configure log collection with Promtail

### Pending (Being resolved):
- 🔧 Fix Traefik TLS/SNI configuration
- 🔧 Enable HTTPS access via *.homelab.grenlan.com
- 🔧 Deploy remaining services (MinIO, etc.)

## Summary

Your homelab monitoring stack is **fully operational** and accessible via HTTP. All core services (Grafana, Prometheus, Loki) are running and healthy on pi-a (192.168.1.12). 

**Recommended Access Method:** Use direct HTTP URLs from your local network or SSH tunneling for secure remote access.

---

*For questions or issues, check the logs:*
```bash
# Service logs
ssh pi@192.168.1.12 "journalctl -u grafana-server -n 50"
ssh pi@192.168.1.12 "journalctl -u prometheus -n 50"
ssh pi@192.168.1.12 "podman logs loki"
```