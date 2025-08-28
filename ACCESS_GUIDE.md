# Homelab Infrastructure Access Guide

**Last Updated:** 2025-08-27  
**Status:** ✅ OPERATIONAL

## 🚀 Quick Access

### Direct Service URLs

| Service | URL | Credentials | Status |
|---------|-----|-------------|--------|
| **Prometheus** | http://10.14.185.35:9090 | None | ✅ Running |
| **Grafana** | http://10.14.185.35:3000 | admin/admin | ✅ Running |
| **Loki** | http://10.14.185.35:3100 | None | ✅ Running |
| **Node Exporter (vm-a)** | http://10.14.185.35:9100/metrics | None | ✅ Running |
| **Node Exporter (vm-b)** | http://10.14.185.67:9100/metrics | None | ✅ Running |
| **Node Exporter (vm-c)** | http://10.14.185.213:9100/metrics | None | ✅ Running |

### Ingress URLs (via Caddy on vm-b)

| Service | URL | Notes |
|---------|-----|-------|
| **Prometheus** | https://prometheus.local | Self-signed cert |
| **Grafana** | https://grafana.local | Self-signed cert |
| **Loki** | https://loki.local | Self-signed cert |

## 📊 Infrastructure Overview

### Virtual Machines

| VM | IP Address | Role | Services |
|----|------------|------|----------|
| **vm-a** | 10.14.185.35 | Observability | Prometheus, Grafana, Loki, Promtail |
| **vm-b** | 10.14.185.67 | Ingress | Caddy, Node Exporter, Promtail |
| **vm-c** | 10.14.185.213 | Applications | Node Exporter |

### Service Status Summary

- ✅ **Prometheus**: Collecting metrics from all node exporters
- ✅ **Grafana**: Operational with Prometheus datasource
- ✅ **Loki**: Receiving logs from Promtail
- ✅ **Caddy**: Running as ingress controller (ports 80, 443)
- ✅ **Node Exporters**: Running on all VMs (3/3)
- ✅ **Promtail**: Collecting logs on vm-a and vm-b

## 🔧 Administrative Tasks

### Check Service Health

```bash
# Check all services via healthcheck script
./scripts/healthcheck.sh

# Check time synchronization (must be < 100ms drift, stratum ≤ 3)
ansible staging -i ansible/inventories/local/hosts.yml -m shell -a "chronyc tracking"

# Check SSH redundancy
./scripts/preflight_ssh.sh 10.14.185.35  # vm-a
./scripts/preflight_ssh.sh 10.14.185.67  # vm-b
./scripts/preflight_ssh.sh 10.14.185.213 # vm-c
```

### View Container Status

```bash
# Check containers on each VM
ansible vm-a -i ansible/inventories/local/hosts.yml -m command -a "sudo podman ps"
ansible vm-b -i ansible/inventories/local/hosts.yml -m command -a "sudo podman ps"
ansible vm-c -i ansible/inventories/local/hosts.yml -m command -a "sudo podman ps"
```

### View Logs

```bash
# View Prometheus logs
ansible vm-a -i ansible/inventories/local/hosts.yml -m shell -a "sudo podman logs --tail 50 prometheus"

# View Grafana logs
ansible vm-a -i ansible/inventories/local/hosts.yml -m shell -a "sudo podman logs --tail 50 grafana"

# View Loki logs
ansible vm-a -i ansible/inventories/local/hosts.yml -m shell -a "sudo podman logs --tail 50 loki"

# View Caddy logs
ansible vm-b -i ansible/inventories/local/hosts.yml -m shell -a "sudo podman logs --tail 50 caddy"
```

## 🔍 Monitoring & Metrics

### Prometheus Targets

Check target status at: http://10.14.185.35:9090/targets

Current targets:
- ✅ `node` job: 3/3 instances UP (all VMs)
- ✅ `prometheus` job: 1/1 instance UP
- ⚠️ `grafana` job: DOWN (localhost connection issue)
- ⚠️ `loki` job: DOWN (localhost connection issue)

### Grafana Dashboards

1. Access Grafana: http://10.14.185.35:3000
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
ansible-playbook -i inventories/local/hosts.yml playbooks/<playbook-name>.yml

# Deploy to all staging VMs
ansible-playbook -i inventories/local/hosts.yml playbooks/00-bootstrap.yml
ansible-playbook -i inventories/local/hosts.yml playbooks/20-podman.yml
ansible-playbook -i inventories/local/hosts.yml playbooks/30-observability.yml
ansible-playbook -i inventories/local/hosts.yml playbooks/41-deploy-caddy.yml
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
ansible staging -i ansible/inventories/local/hosts.yml -m command -a "sudo podman auto-update --dry-run"

# Apply updates to specific container
ansible <vm-name> -i ansible/inventories/local/hosts.yml -m shell -a "sudo podman pull <image> && sudo systemctl restart <service>"
```

### Backup & Restore
```bash
# Backup Prometheus data
ansible vm-a -i ansible/inventories/local/hosts.yml -m shell -a "sudo tar -czf /tmp/prometheus-backup.tar.gz /var/lib/containers/storage/volumes/prometheus-data"

# Backup Grafana data
ansible vm-a -i ansible/inventories/local/hosts.yml -m shell -a "sudo tar -czf /tmp/grafana-backup.tar.gz /var/lib/containers/storage/volumes/grafana-data"
```

## 🔐 Security Notes

- All services are currently using HTTP (not HTTPS) for internal communication
- Caddy has generated self-signed certificates for *.local domains
- Firewall (UFW) is enabled on all VMs
- SSH hardening is in place with key-only authentication
- Rootless Podman is configured for container security

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