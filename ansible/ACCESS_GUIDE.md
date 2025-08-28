# Raspberry Pi Cluster Access Guide
Generated: 2025-08-27
Last Updated: 2025-08-27 00:40 UTC

## Deployment Status

| Service | Node | Status | Access Method |
|---------|------|--------|---------------|
| Prometheus | pi-a | ✅ Running | http://pi-a.grenlan.com:9090 |
| Grafana | pi-a | ✅ Running | http://pi-a.grenlan.com:3000 |
| Node Exporters | All | ✅ Running | Port 9100 on each node |
| Traefik | pi-b | ✅ Running | http://pi-b.grenlan.com:8080/dashboard/ |
| MinIO | pi-d | ✅ Running | http://pi-d.grenlan.com:9001 (console) |
| NFS Server | pi-d | ✅ Running | Standard NFS mount commands |

## Cluster Overview

Your 4-node Raspberry Pi cluster is now configured with the following architecture:

| Node | Hostname | IP Address | Role | Services |
|------|----------|------------|------|----------|
| pi-a | pi-a.grenlan.com | 192.168.1.12 | Monitoring | Prometheus, Grafana, Loki |
| pi-b | pi-b.grenlan.com | 192.168.1.11 | Ingress | Traefik, Nginx |
| pi-c | pi-c.grenlan.com | 192.168.1.10 | Worker | Application Containers |
| pi-d | pi-d.grenlan.com | 192.168.1.13 | Storage | MinIO, NFS, Samba, Backups |

## SSH Access

### Primary Access (using domain names)
```bash
ssh pi@pi-a.grenlan.com  # Monitoring node
ssh pi@pi-b.grenlan.com  # Ingress node
ssh pi@pi-c.grenlan.com  # Worker node
ssh pi@pi-d.grenlan.com  # Storage node
```

### Direct IP Access (fallback)
```bash
ssh pi@192.168.1.12  # pi-a
ssh pi@192.168.1.11  # pi-b
ssh pi@192.168.1.10  # pi-c
ssh pi@192.168.1.13  # pi-d
```

### Credentials
- **Primary user**: `pi` (key-based authentication)
- **Admin user**: `william` (passwordless sudo)
- **Emergency user**: `breakfix` (for recovery)
- **Default password**: TempPiPass2024!Change (should be changed)

## Web Services

### Monitoring Stack (pi-a)

#### Prometheus
- **URL**: http://pi-a.grenlan.com:9090
- **Direct**: http://192.168.1.12:9090
- **Purpose**: Metrics collection and storage
- **Status**: ✅ Running (native service)

#### Grafana
- **URL**: http://pi-a.grenlan.com:3000
- **Direct**: http://192.168.1.12:3000
- **Purpose**: Metrics visualization
- **Default login**: admin/admin
- **Status**: ✅ Running with Prometheus datasource configured
- **Dashboard**: Node Exporter Full imported (ID 1860)

#### Node Exporter
- **URL**: http://pi-a.grenlan.com:9100/metrics
- **Direct**: http://192.168.1.12:9100/metrics
- **Purpose**: System metrics
- **Status**: ✅ Running on all nodes

### Ingress Services (pi-b)

#### Traefik Dashboard
- **URL**: http://pi-b.grenlan.com:8080/dashboard/
- **Direct**: http://192.168.1.11:8080/dashboard/
- **Purpose**: Reverse proxy and load balancer
- **Status**: ✅ Running (Podman container)
- **Routes configured**: Grafana, Prometheus, MinIO

#### Nginx
- **URL**: http://pi-b.grenlan.com
- **Direct**: http://192.168.1.11
- **Purpose**: Web server
- **Status**: ✅ Running

### Storage Services (pi-d)

#### MinIO Console
- **URL**: http://pi-d.grenlan.com:9001
- **API**: http://pi-d.grenlan.com:9000
- **Direct Console**: http://192.168.1.13:9001
- **Direct API**: http://192.168.1.13:9000
- **Purpose**: S3-compatible object storage
- **Status**: ✅ Running (Podman container)
- **Credentials**: admin / minio123456

#### NFS Shares
```bash
# Mount NFS shares from other nodes
sudo mount -t nfs pi-d.grenlan.com:/storage/nfs/shared /mnt/shared
sudo mount -t nfs 192.168.1.13:/storage/backups /mnt/backups
```

#### Samba/SMB Shares
```bash
# Windows/Mac access
\\pi-d.grenlan.com\storage
\\192.168.1.13\backups

# Linux mount
sudo mount -t cifs //pi-d.grenlan.com/storage /mnt/storage -o username=pi
```

## Container Management

### Podman Commands
```bash
# List all containers
podman ps -a

# View container logs
podman logs <container-name>

# Start/stop containers
podman start <container-name>
podman stop <container-name>

# Execute commands in container
podman exec -it <container-name> /bin/bash
```

### Systemd Service Management
```bash
# Check service status
systemctl status <service-name>

# Start/stop/restart services
sudo systemctl start <service-name>
sudo systemctl stop <service-name>
sudo systemctl restart <service-name>

# Enable/disable auto-start
sudo systemctl enable <service-name>
sudo systemctl disable <service-name>
```

## Storage Layout (pi-d)

The 1TB USB drive is mounted at `/storage` with the following structure:

```
/storage/
├── backups/
│   ├── daily/     # Daily backups (7 days retention)
│   ├── weekly/    # Weekly backups (30 days)
│   ├── monthly/   # Monthly backups (365 days)
│   └── cluster/   # Full cluster backups
├── volumes/
│   ├── prometheus/
│   ├── grafana/
│   ├── loki/
│   └── apps/
├── nfs/
│   ├── shared/    # Shared network storage
│   ├── backups/
│   └── volumes/
├── minio-data/    # Object storage data
├── database-backups/
└── archive/
```

## Ansible Management

### Running Playbooks
```bash
cd ~/git/podman-homelab/ansible

# Run specific playbook
ansible-playbook playbooks/30-observability.yml

# Run with specific inventory
ansible-playbook -i inventories/prod/hosts.yml playbooks/10-base.yml

# Dry run (check mode)
ansible-playbook playbooks/20-podman.yml --check --diff

# Run on specific hosts
ansible-playbook playbooks/40-ingress.yml --limit pi-b
```

### Ad-hoc Commands
```bash
# Ping all nodes
ansible -i inventories/prod/hosts.yml pis -m ping

# Check disk usage
ansible pis -a "df -h"

# Restart a service
ansible pi-a -m systemd -a "name=prometheus state=restarted" --become
```

## Monitoring & Health Checks

### Time Synchronization
```bash
# Check time sync status (requirement: <100ms drift, stratum ≤3)
chronyc tracking

# Force time sync
sudo chronyc makestep
```

### System Health
```bash
# Check system resources
htop

# Check disk usage
df -h

# Check memory
free -h

# Check service logs
journalctl -u <service-name> -f
```

### Network Connectivity
```bash
# Test node connectivity
for node in pi-a pi-b pi-c pi-d; do
  echo "Testing $node..."
  ping -c 1 $node.grenlan.com
done

# Check open ports
sudo ss -tulpn
```

## Backup & Recovery

### Manual Backup
```bash
# Run cluster backup on pi-d
ssh pi@pi-d.grenlan.com
sudo /usr/local/bin/backup-cluster.sh

# Check backup status
ls -la /storage/backups/daily/
```

### Automated Backups
- Daily: 2:00 AM to `/storage/backups/daily`
- Weekly: Sundays to `/storage/backups/weekly`
- Monthly: 1st day to `/storage/backups/monthly`

### Recovery
```bash
# Restore from backup
rsync -avz /storage/backups/daily/latest/ /home/pi/restore/

# Restore specific service data
rsync -avz pi-d.grenlan.com:/storage/backups/daily/latest/prometheus/ /home/pi/volumes/prometheus/
```

## Troubleshooting

### Common Issues

#### SSH Connection Refused
```bash
# Check SSH service
sudo systemctl status ssh

# Check firewall
sudo ufw status

# Verify SSH config
sudo sshd -t
```

#### Service Not Starting
```bash
# Check logs
journalctl -xe
journalctl -u <service-name> --since "10 minutes ago"

# Check configuration
<service-name> --config-test
```

#### Container Issues
```bash
# Check podman service
systemctl --user status podman.socket

# Reset podman
podman system reset

# Check container logs
podman logs --tail 50 <container-name>
```

#### Storage Issues
```bash
# Check mount status
mount | grep storage

# Remount storage
sudo mount -a

# Check disk health
sudo smartctl -a /dev/sda
```

## Security Notes

1. **Firewall**: UFW is enabled on all nodes with specific port allowances
2. **SSH**: Key-based authentication only, password auth disabled
3. **Updates**: Unattended security updates are enabled
4. **Time Sync**: Enforced <100ms drift for security protocols
5. **Network Segmentation**: Services bound to specific interfaces

## Quick Commands Reference

```bash
# Access monitoring
firefox http://pi-a.grenlan.com:3000  # Grafana
firefox http://pi-a.grenlan.com:9090  # Prometheus

# Deploy changes
cd ~/git/podman-homelab/ansible
./deploy-all.sh

# Check cluster status
ansible -i inventories/prod/hosts.yml pis -m ping
ansible pis -a "podman ps"

# View logs
ssh pi@pi-a.grenlan.com journalctl -f
ssh pi@pi-b.grenlan.com journalctl -u traefik

# Backup now
ssh pi@pi-d.grenlan.com sudo /usr/local/bin/backup-cluster.sh
```

## Support Information

- **Documentation**: This guide at `/home/william/git/podman-homelab/ansible/ACCESS_GUIDE.md`
- **Configuration**: CLAUDE.md for operational guidelines
- **Ansible Playbooks**: `/home/william/git/podman-homelab/ansible/playbooks/`
- **Emergency Access**: Use `breakfix` user if primary access fails