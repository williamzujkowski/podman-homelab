# Homelab Operations Guide

## Overview

This document provides operational procedures for managing the Podman-based homelab infrastructure deployed across staging VMs and production Raspberry Pis.

## Infrastructure Layout

### Staging Environment
- **vm-a** (10.14.185.35): Monitoring stack (Prometheus, Loki, Grafana)
- **vm-b** (10.14.185.67): Ingress controller (Caddy)
- **vm-c** (10.14.185.213): Worker node

### Production Environment (Future)
- **pi-a**: Canary deployment target
- **pi-b, pi-c, pi-d**: Production cluster

## Service Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│    vm-a      │     │    vm-b      │     │    vm-c      │
├──────────────┤     ├──────────────┤     ├──────────────┤
│ Prometheus   │     │ Caddy        │     │ Node Export  │
│ Loki         │────▶│ (Ingress)    │     │ Promtail     │
│ Grafana      │     │ Node Export  │     └──────────────┘
│ Node Export  │     │ Promtail     │
│ Promtail     │     └──────────────┘
└──────────────┘
```

## Daily Operations

### Health Checks

Run the automated health check:
```bash
./scripts/healthcheck.sh
```

This verifies:
- SSH connectivity to all VMs
- Service availability (Grafana, Prometheus, Loki, Caddy)
- Node exporter metrics collection
- Container health status

### Accessing Services

Due to Multipass networking limitations, use SSH tunnels:

```bash
# Create tunnels
./scripts/create-tunnels.sh

# Access services
# Grafana:    http://localhost:3000 (admin/admin)
# Prometheus: http://localhost:9090
# Loki:       http://localhost:3100
# Caddy:      http://localhost:8080
```

### Viewing Logs

Check service logs on any VM:
```bash
# Container logs
ssh vm-a 'sudo podman logs grafana --tail 50'
ssh vm-a 'sudo podman logs prometheus --tail 50'

# System logs
ssh vm-a 'sudo journalctl -u grafana.service -n 50'
```

## Deployment Procedures

### 1. Local Development

```bash
# Lint and validate
yamllint .
ansible-lint ansible/

# Test locally with Molecule
cd ansible/roles/base
molecule test
```

### 2. Deploy to Staging

```bash
cd ansible
ansible-playbook -i inventories/local/hosts.yml playbooks/site.yml

# Or use GitHub Actions (automatic on main branch push)
```

### 3. Production Deployment (Future)

Production deployments follow a canary pattern:
1. Deploy to pi-a (canary)
2. Monitor for 30 minutes
3. If healthy, deploy to remaining nodes
4. If issues, rollback using digest

## Troubleshooting

### Service Won't Start

1. Check logs:
```bash
ssh <vm> 'sudo journalctl -u <service>.service -n 100'
```

2. Check container status:
```bash
ssh <vm> 'sudo podman ps -a'
```

3. Restart service:
```bash
ssh <vm> 'sudo systemctl restart <service>.service'
```

### Network Connectivity Issues

1. Verify firewall rules:
```bash
ssh <vm> 'sudo ufw status numbered'
```

2. Check service binding:
```bash
ssh <vm> 'sudo ss -tlnp | grep <port>'
```

3. Test connectivity:
```bash
ssh <vm> 'curl -v http://localhost:<port>/health'
```

### Grafana Issues

1. Reset admin password:
```bash
ssh vm-a 'sudo podman exec grafana grafana-cli admin reset-admin-password newpassword'
```

2. Check datasources:
```bash
curl -u admin:admin http://localhost:3000/api/datasources
```

### Prometheus Issues

1. Check targets:
```bash
curl http://localhost:9090/api/v1/targets
```

2. Validate config:
```bash
ssh vm-a 'sudo podman exec prometheus promtool check config /etc/prometheus/prometheus.yml'
```

## Monitoring & Alerting

### Key Metrics to Watch

1. **Node Health**
   - CPU usage < 80%
   - Memory usage < 90%
   - Disk usage < 85%
   - Load average < 4

2. **Service Availability**
   - All exporters up
   - Prometheus scrape success > 95%
   - Grafana API responding

### Alert Rules

Alerts are defined in:
- `ansible/roles/prometheus/files/alerts/node-alerts.yml`

Current alerts:
- NodeDown: Node exporter unreachable for 5m
- HighCPUUsage: CPU > 80% for 10m
- HighMemoryUsage: Memory > 90% for 5m
- DiskSpaceLow: Disk > 85% for 10m
- ServiceDown: Core services unavailable

## Backup & Recovery

### Configuration Backup

All configuration is in Git. To backup runtime data:

```bash
# Backup Grafana dashboards
ssh vm-a 'sudo podman exec grafana grafana-cli admin export-dashboard'

# Backup Prometheus data
ssh vm-a 'sudo podman exec prometheus tar czf /tmp/prometheus-data.tar.gz /prometheus'
ssh vm-a 'sudo podman cp prometheus:/tmp/prometheus-data.tar.gz .'
scp vm-a:prometheus-data.tar.gz backups/
```

### Disaster Recovery

1. Recreate VMs:
```bash
./scripts/multipass-setup.sh
```

2. Redeploy services:
```bash
cd ansible
ansible-playbook -i inventories/local/hosts.yml playbooks/site.yml
```

3. Restore data from backups if needed

## Security Considerations

1. **SSH Access**
   - Key-based authentication only
   - Tailscale SSH as backup (port 22)
   - Regular key rotation

2. **Container Security**
   - Rootless containers where possible
   - Digest-pinned images
   - No auto-update in production

3. **Network Security**
   - UFW firewall enabled
   - Minimal port exposure
   - Service-to-service communication isolated

## Performance Tuning

### Prometheus

Adjust scrape intervals in `prometheus.yml`:
```yaml
global:
  scrape_interval: 15s  # Reduce for more granular data
  evaluation_interval: 15s
```

### Grafana

Optimize dashboard queries:
- Use recording rules for complex queries
- Limit time ranges in dashboards
- Enable query caching

### System Resources

Monitor and adjust:
```bash
# Check resource usage
ssh <vm> 'free -h && df -h && top -bn1 | head -20'

# Adjust container limits if needed
# Edit quadlet files in /etc/containers/systemd/
```

## Maintenance Windows

### Weekly Tasks
- Review alerts and metrics
- Check for security updates
- Verify backups

### Monthly Tasks
- Update container images (staging first)
- Review and optimize dashboards
- Clean up old logs

### Quarterly Tasks
- Full disaster recovery test
- Security audit
- Performance review

## Contact & Escalation

For issues:
1. Check this operations guide
2. Review logs and metrics
3. Consult CLAUDE.md for deployment procedures
4. Open GitHub issue for persistent problems

## Quick Reference

### Common Commands

```bash
# VM management
multipass list
multipass shell vm-a

# Service control
ssh vm-a 'sudo systemctl status grafana'
ssh vm-a 'sudo systemctl restart prometheus'

# Container management
ssh vm-a 'sudo podman ps'
ssh vm-a 'sudo podman logs --tail 50 loki'

# Network debugging
ssh vm-a 'sudo ss -tlnp'
ssh vm-a 'sudo iptables -L -n'

# Quick health check
for vm in vm-a vm-b vm-c; do 
  echo "=== $vm ===" 
  ssh $vm 'sudo podman ps --format "table {{.Names}}\t{{.Status}}"'
done
```

### Service URLs (via SSH tunnels)

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3000 | admin/admin |
| Prometheus | http://localhost:9090 | None |
| Loki | http://localhost:3100 | None |
| Caddy | http://localhost:8080 | None |

### Key File Locations

| Component | Location |
|-----------|----------|
| Ansible playbooks | `ansible/playbooks/` |
| Quadlet definitions | `quadlet/` |
| Prometheus config | `/etc/prometheus/prometheus.yml` (on vm-a) |
| Grafana config | `/etc/grafana/` (on vm-a) |
| Caddy config | `/etc/caddy/Caddyfile` (on vm-b) |

---

*Last updated: 2025-08-26*