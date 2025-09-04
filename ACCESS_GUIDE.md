# Homelab Infrastructure Access Guide

**Last Updated:** 2025-09-04  
**Environment:** PRODUCTION (Raspberry Pi Cluster)  
**Status:** ✅ OPERATIONAL

## 🚀 Quick Access

### Direct Service URLs (Internal Network Only)

| Service | URL | Credentials | Status |
|---------|-----|-------------|--------|
| **Prometheus** | http://192.168.1.12:9090 | None | ✅ Running |
| **Grafana** | http://192.168.1.12:3000 | admin/admin | ✅ Running |
| **Loki** | http://192.168.1.12:3100 | None | ✅ Running |
| **Authentik** | http://192.168.1.13:9002 | akadmin/vault_password | ✅ Running |
| **Traefik Dashboard** | http://192.168.1.11:8080 | None | ✅ Running |
| **Node Exporter (pi-a)** | http://192.168.1.12:9100/metrics | None | ✅ Running |
| **Node Exporter (pi-b)** | http://192.168.1.11:9100/metrics | None | ✅ Running |
| **Node Exporter (pi-c)** | http://192.168.1.10:9100/metrics | None | ✅ Running |
| **Node Exporter (pi-d)** | http://192.168.1.13:9100/metrics | None | ✅ Running |

### Ingress URLs (via Traefik on pi-b)

| Service | URL | Notes |
|---------|-----|-------|
| **Prometheus** | https://prometheus.homelab.grenlan.com | Let's Encrypt ✅ |
| **Grafana** | https://grafana.homelab.grenlan.com | Let's Encrypt ✅ |
| **Loki** | https://loki.homelab.grenlan.com | Let's Encrypt ✅ |
| **Authentik** | https://auth.homelab.grenlan.com | Let's Encrypt ✅ |

**Note**: Add these to your `/etc/hosts` file:
```
192.168.1.11  homelab.grenlan.com grafana.homelab.grenlan.com prometheus.homelab.grenlan.com loki.homelab.grenlan.com auth.homelab.grenlan.com
```

## 📊 Infrastructure Overview

### Raspberry Pi Cluster

| Node | IP Address | Role | Services |
|------|------------|------|----------|
| **pi-a** | 192.168.1.12 | Monitoring/Canary | Prometheus, Grafana, Loki, Promtail |
| **pi-b** | 192.168.1.11 | Ingress | Traefik, Node Exporter |
| **pi-c** | 192.168.1.10 | Worker/Apps | Application services, Node Exporter |
| **pi-d** | 192.168.1.13 | Storage/Auth | PostgreSQL, Redis, Authentik, MinIO, Node Exporter |

### Service Status Summary

- ✅ **Prometheus**: Collecting metrics from all node exporters
- ✅ **Grafana**: Operational with Prometheus datasource
- ✅ **Loki**: Receiving logs from Promtail
- ✅ **Traefik**: Running as ingress controller (ports 80, 443, 8080)
- ✅ **Authentik**: Identity provider operational (port 9002)
- ✅ **PostgreSQL**: Database backend for Authentik
- ✅ **Node Exporters**: Running on all Pis (4/4)
- ✅ **Promtail**: Collecting logs from all services

## 🔧 Administrative Tasks

### Check Service Health

```bash
# Check all services via healthcheck script
./scripts/healthcheck.sh

# Check time synchronization (must be < 100ms drift, stratum ≤ 3)
ansible pis -i ansible/inventories/prod/hosts.yml -m shell -a "chronyc tracking"

# Check SSH redundancy
./scripts/preflight_ssh.sh 192.168.1.12  # pi-a
./scripts/preflight_ssh.sh 192.168.1.11  # pi-b
./scripts/preflight_ssh.sh 192.168.1.10  # pi-c
./scripts/preflight_ssh.sh 192.168.1.13  # pi-d
```

### View Container Status

```bash
# Check containers on each Pi
ansible pi-a -i ansible/inventories/prod/hosts.yml -m command -a "sudo podman ps"
ansible pi-b -i ansible/inventories/prod/hosts.yml -m command -a "sudo podman ps"
ansible pi-c -i ansible/inventories/prod/hosts.yml -m command -a "sudo podman ps"
ansible pi-d -i ansible/inventories/prod/hosts.yml -m command -a "sudo podman ps"
```

### View Logs

```bash
# View Prometheus logs
ansible pi-a -i ansible/inventories/prod/hosts.yml -m shell -a "sudo podman logs --tail 50 prometheus"

# View Grafana logs
ansible pi-a -i ansible/inventories/prod/hosts.yml -m shell -a "sudo podman logs --tail 50 grafana"

# View Loki logs
ansible pi-a -i ansible/inventories/prod/hosts.yml -m shell -a "sudo podman logs --tail 50 loki"

# View Traefik logs
ansible pi-b -i ansible/inventories/prod/hosts.yml -m shell -a "sudo journalctl -u traefik --tail 50"

# View Authentik logs
ansible pi-d -i ansible/inventories/prod/hosts.yml -m shell -a "sudo podman logs --tail 50 authentik-server"
```

## 🔍 Monitoring & Metrics

### Prometheus Targets

Check target status at: http://192.168.1.12:9090/targets

Current targets:
- ✅ `node` job: 3/3 instances UP (all VMs)
- ✅ `prometheus` job: 1/1 instance UP
- ✅ `grafana` job: 1/1 instance UP
- ✅ `loki` job: 1/1 instance UP
- ✅ `authentik` job: 1/1 instance UP

### Grafana Dashboards

1. Access Grafana: http://192.168.1.12:3000
2. Login: admin/admin
3. Available datasources:
   - Prometheus (configured)
   - Loki (configured)

### Query Examples

#### Prometheus Queries
```promql
# CPU usage per VM
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Disk usage
100 - ((node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100)
```

#### Loki Queries
```logql
# All container logs
{job="containers"}

# Errors across all services
{job="containers"} |= "error"

# Specific container logs
{job="containers", container="prometheus"}
```

## 🚨 Troubleshooting

### Common Issues

#### Service Not Accessible
```bash
# Check if service is running
ansible <vm-name> -i ansible/inventories/local/hosts.yml -m command -a "sudo podman ps"

# Restart service
ansible <vm-name> -i ansible/inventories/local/hosts.yml -m command -a "sudo systemctl restart <service-name>"

# Check logs
ansible <vm-name> -i ansible/inventories/local/hosts.yml -m shell -a "sudo podman logs --tail 100 <container-name>"
```

#### Time Sync Issues
```bash
# Check chrony status
ansible <vm-name> -i ansible/inventories/local/hosts.yml -m command -a "chronyc sources"

# Force sync
ansible <vm-name> -i ansible/inventories/local/hosts.yml -m command -a "sudo chronyc makestep"
```

## 🔄 Deployment Commands

### Apply Configuration Changes
```bash
# Run specific playbook
cd ansible
ansible-playbook -i inventories/prod/hosts.yml playbooks/<playbook-name>.yml

# Deploy to production Pis (follow canary pattern)
ansible-playbook -i inventories/prod/hosts.yml playbooks/00-bootstrap.yml --limit pi-a
ansible-playbook -i inventories/prod/hosts.yml playbooks/20-podman.yml --limit pi-a
ansible-playbook -i inventories/prod/hosts.yml playbooks/30-observability.yml --limit pi-a
# If successful, roll out to remaining nodes
ansible-playbook -i inventories/prod/hosts.yml playbooks/00-bootstrap.yml
ansible-playbook -i inventories/prod/hosts.yml playbooks/20-podman.yml
ansible-playbook -i inventories/prod/hosts.yml playbooks/30-observability.yml
```

### Validate Deployment
```bash
# Run validation script
./scripts/validate_deployment.sh

# Run integration tests
./scripts/integration_tests.sh
```

## 📦 Container Management

### Update Container Images
```bash
# Check for updates (manual - auto-update disabled for stability)
ansible pis -i ansible/inventories/prod/hosts.yml -m command -a "sudo podman auto-update --dry-run"

# Apply updates to specific container
ansible <pi-name> -i ansible/inventories/prod/hosts.yml -m shell -a "sudo podman pull <image> && sudo systemctl restart <service>"
```

### Backup & Restore
```bash
# Backup Prometheus data
ansible pi-a -i ansible/inventories/prod/hosts.yml -m shell -a "sudo tar -czf /tmp/prometheus-backup.tar.gz /var/lib/containers/storage/volumes/prometheus-data"

# Backup Grafana data
ansible pi-a -i ansible/inventories/prod/hosts.yml -m shell -a "sudo tar -czf /tmp/grafana-backup.tar.gz /var/lib/containers/storage/volumes/grafana-data"

# Backup to pi-d (storage node)
ansible pi-a -i ansible/inventories/prod/hosts.yml -m shell -a "sudo rsync -avz /tmp/*.tar.gz pi@192.168.1.13:/storage/backups/"
```

## 🔐 Security Notes

- Internal services use HTTPS with Let's Encrypt certificates (90-day auto-renewal)
- Services are only accessible from local network (192.168.1.0/24)
- No public internet access - DNS records are not proxied through Cloudflare
- Firewall (UFW) is enabled on all Pis with strict ingress rules
- SSH hardening is in place with key-only authentication
- Rootless Podman is configured for container security
- Time synchronization enforced (< 100ms drift, stratum ≤ 3)

## 🌐 Cloudflare Integration

### Certificate Management
- **Type**: Let's Encrypt with Cloudflare DNS-01 challenge
- **Validity**: 90 days (auto-renewal ~30 days before expiry)
- **Coverage**: `*.homelab.grenlan.com`, `homelab.grenlan.com`
- **Location**: `/etc/letsencrypt/live/homelab.grenlan.com/` on pi-b

### DNS Configuration
```bash
# Add to your local /etc/hosts file:
192.168.1.11  homelab.grenlan.com
192.168.1.11  grafana.homelab.grenlan.com
192.168.1.11  prometheus.homelab.grenlan.com
192.168.1.11  loki.homelab.grenlan.com
192.168.1.11  auth.homelab.grenlan.com
```

### Certificate Setup
```bash
# Check certificate status
ssh pi@192.168.1.11 "sudo /opt/certbot-env/bin/certbot certificates"

# Manual renewal test
ssh pi@192.168.1.11 "sudo /opt/certbot-env/bin/certbot renew --dry-run"

# View renewal timer status
ssh pi@192.168.1.11 "sudo systemctl status certbot-renew.timer"
```

### Network Security
- Services blocked from external access via Traefik rules
- Only accessible from: 192.168.1.0/24 (internal network)
- External requests blocked by firewall (UFW)
- Authentication via Authentik for protected services

## 📝 Next Steps for Production

1. **TLS Certificates**: Implement proper TLS with Let's Encrypt or internal CA
2. **Authentication**: Add authentication to Prometheus and Loki
3. **Monitoring**: Create comprehensive Grafana dashboards
4. **Alerting**: Configure Prometheus alerting rules and AlertManager
5. **Backup Strategy**: Implement automated backups for persistent data
6. **High Availability**: Consider HA setup for critical services
7. **Network Segmentation**: Implement VLANs or network policies
8. **Secret Management**: Use Ansible Vault or external secret manager

## 🆘 Support

For issues or questions:
1. Check logs using commands above
2. Review CLAUDE.md for operational guidelines
3. Check deployment status in DEPLOYMENT_STATUS.md
4. Follow rollback procedures if needed

---

**Infrastructure managed by Ansible with GitOps principles**  
**Following CLAUDE.md operational playbook**