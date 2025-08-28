# Deployment Guide

## Current Status ✅

Your homelab infrastructure is now fully defined and ready for deployment. Three Ubuntu 24.04 VMs are running and configured in your inventory.

### VMs Running
- **vm-a** (10.14.185.35) - Observability stack host
- **vm-b** (10.14.185.67) - Ingress controller host  
- **vm-c** (10.14.185.213) - General workload host

### Components Ready
- ✅ Complete Ansible automation framework
- ✅ Podman role with rootless configuration
- ✅ Quadlet service definitions for all services
- ✅ Observability stack (Prometheus, Grafana, Loki, Promtail)
- ✅ Ingress controller (Caddy)
- ✅ CI/CD pipelines configured

## Deployment Steps

### Step 1: Configure SSH Access

First, set up SSH key authentication to the VMs:

```bash
# Generate SSH key if you don't have one
ssh-keygen -t ed25519 -f ~/.ssh/homelab_key -N ""

# Copy key to VMs (use default multipass password)
for vm in vm-a vm-b vm-c; do
  multipass exec $vm -- bash -c "echo '$(cat ~/.ssh/homelab_key.pub)' >> ~/.ssh/authorized_keys"
done

# Update inventory with your SSH key path
export ANSIBLE_PRIVATE_KEY_FILE=~/.ssh/homelab_key
```

### Step 2: Bootstrap the VMs

Initialize the base system configuration:

```bash
# Run bootstrap playbook
ansible-playbook -i ansible/inventories/local/hosts.yml \
  ansible/playbooks/00-bootstrap.yml \
  --ask-pass \
  --ask-become-pass
```

*Note: Use 'ubuntu' as both the SSH and sudo password for Multipass VMs*

### Step 3: Apply Base Configuration

Deploy core system configuration (users, SSH, time sync, security):

```bash
ansible-playbook -i ansible/inventories/local/hosts.yml \
  ansible/playbooks/10-base.yml
```

### Step 4: Install Podman

Deploy the container runtime:

```bash
ansible-playbook -i ansible/inventories/local/hosts.yml \
  ansible/playbooks/20-podman.yml
```

### Step 5: Deploy Observability Stack

Install monitoring and logging services:

```bash
ansible-playbook -i ansible/inventories/local/hosts.yml \
  ansible/playbooks/30-observability.yml
```

### Step 6: Configure Ingress

Set up the ingress controller:

```bash
ansible-playbook -i ansible/inventories/local/hosts.yml \
  ansible/playbooks/40-ingress.yml
```

## Service Access

Once deployed, access your services at:

- **Grafana**: http://10.14.185.35:3000 (admin/admin)
- **Prometheus**: http://10.14.185.35:9090
- **Loki**: http://10.14.185.35:3100
- **Ingress**: http://10.14.185.67

### Via Ingress Routes
- http://10.14.185.67/grafana
- http://10.14.185.67/prometheus
- http://10.14.185.67/metrics

## Verification

### Check Service Status

```bash
# Verify all services are running
ansible all -i ansible/inventories/local/hosts.yml \
  -m shell -a "systemctl list-units --type=service --state=running | grep -E '(prometheus|grafana|loki|promtail|node-exporter|caddy)'"

# Check Podman containers
ansible all -i ansible/inventories/local/hosts.yml \
  -m shell -a "podman ps"
```

### Run Health Checks

```bash
# Test service endpoints
./scripts/verify_services.sh 10.14.185.35 10.14.185.67 10.14.185.213

# Check time synchronization
ansible all -i ansible/inventories/local/hosts.yml \
  -m shell -a "chronyc tracking"
```

## Troubleshooting

### VM Access Issues

If you can't connect to VMs:

```bash
# Check VM status
multipass list

# Restart VMs if needed
multipass restart vm-a vm-b vm-c

# Get shell access
multipass shell vm-a
```

### Service Issues

If services aren't starting:

```bash
# Check logs
ansible vm-a -i ansible/inventories/local/hosts.yml \
  -m shell -a "journalctl -u prometheus.service -n 50"

# Reload systemd and restart service
ansible vm-a -i ansible/inventories/local/hosts.yml \
  -m systemd -a "daemon_reload=yes" --become
ansible vm-a -i ansible/inventories/local/hosts.yml \
  -m systemd -a "name=prometheus.service state=restarted" --become
```

## Next Steps

1. **Configure Grafana Dashboards**
   - Import Node Exporter dashboard (ID: 1860)
   - Configure Loki as a data source
   - Create custom dashboards for your services

2. **Set Up Alerts**
   - Configure Prometheus alerting rules
   - Set up notification channels in Grafana

3. **Deploy Applications**
   - Create Quadlet definitions for your applications
   - Use the existing patterns as templates

4. **Production Readiness**
   - Update container image digests
   - Configure backup strategies
   - Set up monitoring alerts

## Clean Up

To tear down the environment:

```bash
# Stop all services
ansible all -i ansible/inventories/local/hosts.yml \
  -m shell -a "systemctl stop prometheus grafana loki promtail node-exporter caddy" \
  --become

# Remove VMs
./scripts/vm-teardown.sh
```

## CI/CD Pipeline

Your GitHub Actions workflows are configured and ready. On push to main:
- Linting and security scanning will run automatically
- Deploy to staging can be triggered manually
- Production deployments require manual approval

Monitor your pipelines at: https://github.com/williamzujkowski/podman-homelab/actions