# Production Deployment Guide

## Prerequisites

### Hardware Requirements
- Raspberry Pi 4B+ (4GB+ RAM recommended)
- SD Card (32GB+ Class 10)
- Network connectivity (Ethernet preferred)

### Software Requirements
- Ubuntu Server 24.04 LTS for Pi
- Ansible 2.15+ on control machine
- SSH key pair for authentication

## Pre-deployment Checklist

### 1. Time Synchronization Gate
```bash
scripts/preflight_time.sh
```
- Drift must be ≤100ms
- Stratum must be ≤3
- Uses Cloudflare NTS + NIST servers

### 2. SSH Redundancy Check
```bash
scripts/preflight_ssh.sh <target_host>
```
- Verify OpenSSH access
- Test Tailscale SSH (optional)

## Deployment Workflow

### Stage 1: Bootstrap
```bash
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/00-bootstrap.yml \
  --private-key ~/.ssh/prod_key \
  -e ansible_become_pass=$ANSIBLE_PASS
```

### Stage 2: Base Configuration  
```bash
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/10-base.yml \
  --private-key ~/.ssh/prod_key \
  -e ansible_become_pass=$ANSIBLE_PASS
```

Configures:
- User accounts (william, breakfix)
- SSH hardening
- Chrony NTS time sync
- Tailscale mesh networking
- UFW firewall rules
- Unattended upgrades

### Stage 3: Podman Runtime
```bash
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/20-podman.yml \
  --private-key ~/.ssh/prod_key \
  -e ansible_become_pass=$ANSIBLE_PASS
```

Installs:
- Podman 4.9.3+
- Quadlet systemd integration
- Auto-update timer (daily at 02:00)
- Container networking (netavark)

### Stage 4: Observability Stack
```bash
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/30-observability.yml \
  --private-key ~/.ssh/prod_key \
  -e ansible_become_pass=$ANSIBLE_PASS
```

Deploys:
- Prometheus (metrics collection)
- Grafana (visualization)
- Loki (log aggregation)
- Promtail (log shipping)
- Node Exporter (system metrics)

### Stage 5: Ingress Controller
```bash
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/40-ingress.yml \
  --private-key ~/.ssh/prod_key \
  -e ansible_become_pass=$ANSIBLE_PASS
```

## Service Architecture

### Node Roles
- **Pi-A**: Observability stack (Prometheus, Grafana, Loki)
- **Pi-B**: Ingress controller (Caddy)
- **Pi-C**: Application services

### Network Ports
| Service | Port | Description |
|---------|------|-------------|
| Prometheus | 9090 | Metrics server |
| Grafana | 3000 | Web UI |
| Loki | 3100 | Log aggregator |
| Node Exporter | 9100 | System metrics |
| Caddy | 80/443 | HTTP/HTTPS ingress |

## Container Management

### Using Quadlet
Services are defined in `/etc/containers/systemd/*.container`

View service status:
```bash
systemctl status prometheus.service
```

Restart service:
```bash
systemctl restart prometheus.service
```

View logs:
```bash
journalctl -u prometheus.service -f
```

### Auto-updates
Containers with label `io.containers.autoupdate=registry` are updated daily.

Manual update:
```bash
systemctl start podman-auto-update.service
```

## Rollback Procedures

### Container Rollback
1. Note previous digest from deployment logs
2. Update Quadlet file with previous digest
3. Restart service

Example:
```bash
# Edit /etc/containers/systemd/prometheus.container
Image=docker.io/prom/prometheus:v2.48.0@sha256:<old_digest>
systemctl daemon-reload
systemctl restart prometheus.service
```

### Configuration Rollback
```bash
# Revert Ansible changes
git checkout <previous_commit> ansible/
# Re-run playbook
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/<playbook>.yml \
  --private-key ~/.ssh/prod_key
```

## Monitoring & Alerts

### Health Checks
```bash
# Run validation script
scripts/validate_deployment.sh

# Check individual services
curl http://<pi-ip>:9090/-/ready  # Prometheus
curl http://<pi-ip>:3000/api/health  # Grafana
curl http://<pi-ip>:3100/ready  # Loki
```

### Key Metrics to Monitor
- CPU usage per container
- Memory usage per container
- Disk I/O
- Network throughput
- Container restart count

## Security Considerations

### SSH Access
- Two SSH planes maintained (OpenSSH + Tailscale)
- Key-only authentication
- Fail2ban protection

### Container Security
- Rootless containers where possible
- Seccomp profiles enabled
- Read-only root filesystems
- No privileged containers

### Network Security  
- UFW firewall with strict rules
- Internal network segmentation
- No public internet exposure

## Troubleshooting

### Common Issues

**Podman storage mismatch**
```bash
sudo rm -rf /var/lib/containers/storage/*
sudo podman system reset -f
```

**Service won't start**
```bash
# Check for port conflicts
sudo ss -tlnp | grep <port>
# Check service logs
journalctl -xeu <service>.service
```

**Time sync issues**
```bash
sudo chronyc sources
sudo chronyc tracking
```

## GitHub CI/CD Integration

### Environment Gates
- `staging`: Auto-deploy to test VMs
- `prod`: Requires manual approval

### Workflow Triggers
```bash
# Manual deployment
gh workflow run deploy-prod.yml \
  --ref main \
  -f environment=prod \
  -f target=pi-a
```

## Maintenance Windows

### Recommended Schedule
- **Daily**: Auto-update containers (02:00)
- **Weekly**: Security patches (Sunday 03:00)  
- **Monthly**: Full system updates
- **Quarterly**: Pi firmware updates

## Contact & Support

- Repository: github.com/yourusername/podman-homelab
- Issues: github.com/yourusername/podman-homelab/issues
- Break-glass account: `breakfix` (console only)