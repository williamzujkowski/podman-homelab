# Pi Cluster Deployment Guide

## Overview

This guide describes the deployment of monitoring and ingress services to the Raspberry Pi production cluster using Ansible.

## Current Production Setup

- **pi-a** (192.168.1.12): Monitoring node
  - Prometheus (native systemd service)
  - Grafana (native systemd service)
  - Loki (Podman container)
  - Node Exporter
  - Promtail

- **pi-b** (192.168.1.11): Ingress node
  - Traefik (Podman container) with Let's Encrypt certificates
  - Node Exporter
  - Promtail

- **pi-c** (192.168.1.10): Worker node
  - Node Exporter
  - Promtail
  - Ready for application deployment

- **pi-d** (192.168.1.13): Storage node
  - Node Exporter
  - Promtail
  - Ready for MinIO deployment

## Prerequisites

1. **Base System Setup**: Run playbooks in order:
   ```bash
   ansible-playbook -i inventories/prod/hosts.yml playbooks/00-bootstrap.yml
   ansible-playbook -i inventories/prod/hosts.yml playbooks/10-base.yml
   ansible-playbook -i inventories/prod/hosts.yml playbooks/20-podman.yml
   ```

2. **Time Synchronization**: Verify all nodes meet CLAUDE.md requirements:
   - Drift ≤ 100ms
   - Stratum ≤ 3
   - chrony with Cloudflare NTS + NIST servers

3. **SSH Redundancy**: Ensure both OpenSSH and Tailscale SSH are available

## Deployment Commands

### 1. Deploy Observability Stack

Deploy Node Exporter and Promtail to all nodes, plus monitoring services to pi-a:

```bash
cd ansible
ANSIBLE_CONFIG=ansible-production.cfg ansible-playbook \
  -i inventories/prod/hosts.yml \
  playbooks/30-observability.yml
```

**Canary Deployment** (CLAUDE.md compliance):
```bash
# Deploy to pi-a first
ANSIBLE_CONFIG=ansible-production.cfg ansible-playbook \
  -i inventories/prod/hosts.yml \
  playbooks/30-observability.yml \
  --limit canary

# Then deploy to all nodes after verification
ANSIBLE_CONFIG=ansible-production.cfg ansible-playbook \
  -i inventories/prod/hosts.yml \
  playbooks/30-observability.yml \
  --limit production_full
```

### 2. Deploy Ingress Controller

Deploy Traefik to pi-b:

```bash
ANSIBLE_CONFIG=ansible-production.cfg ansible-playbook \
  -i inventories/prod/hosts.yml \
  playbooks/41-ingress-pi.yml
```

## Service URLs

After deployment, services will be accessible at:

### Monitoring (pi-a)
- **Prometheus**: http://192.168.1.12:9090
- **Grafana**: http://192.168.1.12:3000 (admin/admin)
- **Loki**: http://192.168.1.12:3100

### Ingress (pi-b)
- **Traefik Dashboard**: http://192.168.1.11:8080/dashboard/
- **Traefik API**: http://192.168.1.11:8080/api/version
- **Metrics**: http://192.168.1.11:8082/metrics

### Node Exporters (all nodes)
- **pi-a**: http://192.168.1.12:9100/metrics
- **pi-b**: http://192.168.1.11:9100/metrics
- **pi-c**: http://192.168.1.10:9100/metrics
- **pi-d**: http://192.168.1.13:9100/metrics

### With Ingress Routing
- **Prometheus**: https://prometheus.homelab.grenlan.com
- **Grafana**: https://grafana.homelab.grenlan.com
- **Loki**: https://loki.homelab.grenlan.com

## Configuration

### Monitoring Configuration

- **Prometheus**: Native service with 60-day retention, 50GB size limit
- **Grafana**: Native service with SQLite database, provisioned datasources
- **Loki**: Container with 7-day retention, filesystem storage
- **Node Exporter**: Native service with Pi-specific collectors
- **Promtail**: Container collecting journald and syslog

### Ingress Configuration

- **Traefik**: v3.1 container with Let's Encrypt certificates
- **SSL**: Cloudflare DNS challenge for *.homelab.grenlan.com
- **Security**: Custom headers, rate limiting, HTTPS redirect
- **Monitoring**: Prometheus metrics on port 8082

## Role Structure

### Monitoring Role (`roles/monitoring/`)
- Deploys Prometheus, Grafana, and Loki
- Configures data sources and dashboards
- Handles both native and container deployments

### Ingress Role (`roles/ingress/`)
- Deploys Traefik reverse proxy
- Manages SSL certificates via certbot + Cloudflare
- Configures dynamic routing and middleware

### Node Exporter Role (`roles/node_exporter/`)
- Installs native Node Exporter
- Includes Pi-specific hardware collectors
- Custom textfile collectors for APT updates

### Promtail Role (`roles/promtail/`)
- Deploys Promtail container
- Collects journald and file logs
- Routes to Loki on monitoring node

## Security

- **Firewall**: UFW enabled with specific port rules
- **Users**: Dedicated service users for native services
- **SSL**: Let's Encrypt certificates with Cloudflare DNS challenge
- **Access**: Internal network access only (192.168.1.0/24)

## Troubleshooting

### Check Service Status
```bash
# On monitoring node (pi-a)
sudo systemctl status prometheus grafana-server
sudo podman ps # For Loki container

# On ingress node (pi-b)
sudo podman ps # For Traefik container

# On all nodes
sudo systemctl status node_exporter
sudo podman ps # For Promtail container
```

### Validate Deployment
```bash
# Run built-in validation
sudo /usr/local/bin/validate-ingress.sh  # On pi-b

# Check connectivity
curl http://192.168.1.12:9090/api/v1/status/config
curl http://192.168.1.11:8080/api/version
```

### Common Issues

1. **Time sync failures**: Run `chronyc tracking` and ensure NTS is working
2. **Container failures**: Check `journalctl -u <service>.service`
3. **Port conflicts**: Verify no other services using the same ports
4. **DNS issues**: Verify Cloudflare credentials for Let's Encrypt

## Rollback

If deployment fails, rollback using digest-pinned containers:

```bash
# Stop failed services
sudo systemctl stop <service>
sudo podman stop <container>

# Revert to previous working configuration
# Use git to restore previous playbook state
git checkout <previous-commit> ansible/playbooks/

# Redeploy with previous configuration
```

## Updates

Follow the CLAUDE.md workflow for updates:

1. Update role defaults with new versions
2. Test in staging/VM environment first
3. Use canary deployment pattern
4. Pin container digests, not tags
5. Use Renovate for automated update PRs