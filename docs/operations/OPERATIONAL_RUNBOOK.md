# Homelab Operational Runbook

**Version:** 2.0.0  
**Last Updated:** September 4, 2025  
**Environment:** Production Raspberry Pi Cluster  
**Target Audience:** Operations team and system administrators

---

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Emergency Procedures](#emergency-procedures)  
3. [Service Management](#service-management)
4. [Monitoring & Alerting](#monitoring--alerting)
5. [Backup & Recovery](#backup--recovery)
6. [Troubleshooting Guides](#troubleshooting-guides)
7. [Maintenance Procedures](#maintenance-procedures)
8. [Change Management](#change-management)

---

## Daily Operations

### Morning Health Check (5 minutes)

**Automated Health Verification:**
```bash
# Run comprehensive health check
./scripts/verify_services.sh

# Expected output: All services should show "✅ HEALTHY"
```

**Manual Verification Commands:**
```bash
# Check all service endpoints
curl -sf http://192.168.1.12:9090/-/healthy    # Prometheus
curl -sf http://192.168.1.12:3000/api/health   # Grafana  
curl -sf http://192.168.1.12:3100/ready        # Loki
curl -sf http://192.168.1.13:9002/-/health/live/ # Authentik
curl -sf http://192.168.1.11:8080/ping         # Traefik

# Check certificate status
ssh pi@192.168.1.11 "sudo /opt/certbot-env/bin/certbot certificates"

# Time synchronization check
ansible all -i ansible/inventories/prod/hosts.yml -m shell -a "chronyc tracking" | grep "System time"
```

### Resource Monitoring (2 minutes)

**Check Resource Usage:**
```bash
# System resource overview
ansible all -i ansible/inventories/prod/hosts.yml -m shell -a "df -h / && free -h && uptime"

# Container resource usage
for node in 192.168.1.{10,11,12,13}; do
  echo "=== $node ==="
  ssh pi@$node "podman ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
done

# Network connectivity test
ansible all -i ansible/inventories/prod/hosts.yml -m ping
```

### Log Review (3 minutes)

**Check for Errors:**
```bash
# Recent system errors
ansible all -i ansible/inventories/prod/hosts.yml -m shell -a "journalctl --since '1 hour ago' --priority=err --no-pager"

# Service-specific logs (if issues detected)
ssh pi@192.168.1.12 "podman logs --since 1h grafana | tail -20"
ssh pi@192.168.1.13 "podman logs --since 1h authentik | tail -20"

# Certificate renewal logs
ssh pi@192.168.1.11 "journalctl -u certbot-renew --since '24 hours ago' --no-pager"
```

### Dashboard Review (2 minutes)

**Grafana Monitoring Dashboard:**
1. Open: `https://grafana.homelab.grenlan.com` (or `http://192.168.1.12:3000`)
2. Login: `admin/admin` (until OAuth2 is configured)
3. Review:
   - Node Overview dashboard
   - Container metrics
   - Certificate expiry status
   - Network traffic patterns

**Key Metrics to Check:**
- CPU usage < 80% on all nodes
- Memory usage < 85% on all nodes  
- Disk usage < 90% on all nodes
- All Prometheus targets "UP"
- Certificate validity > 30 days
- No critical alerts firing

---

## Emergency Procedures

### Service Outage Response

**Immediate Actions (< 5 minutes):**
1. **Identify Scope**: Check which services are affected
2. **Access Method**: Use direct IP addresses to bypass Traefik if needed
3. **Emergency Access**: SSH directly to affected node
4. **Service Status**: Check systemd service status

```bash
# Emergency service check
ssh pi@192.168.1.12 "systemctl --user status podman-*"

# Container status
ssh pi@192.168.1.12 "podman ps -a"

# Immediate restart if needed
ssh pi@192.168.1.12 "systemctl --user restart podman-grafana"
```

### Network Connectivity Issues

**Diagnosis Steps:**
```bash
# Check network connectivity between nodes
for node in 192.168.1.{10,11,12,13}; do
  echo "Testing connectivity to $node:"
  ping -c 3 $node
done

# Check internal service communication
ssh pi@192.168.1.12 "curl -sf http://192.168.1.13:5432"  # Prometheus to PostgreSQL
ssh pi@192.168.1.13 "redis-cli ping"  # Redis connectivity

# DNS resolution test
ssh pi@192.168.1.11 "dig homelab.grenlan.com"
```

### Certificate Emergency

**If HTTPS Access Fails:**
```bash
# Check certificate status
ssh pi@192.168.1.11 "sudo /opt/certbot-env/bin/certbot certificates"

# Manual renewal (if needed)
ssh pi@192.168.1.11 "sudo /opt/certbot-env/bin/certbot renew --dry-run"

# Copy certificates to Traefik (if needed)
ssh pi@192.168.1.11 "sudo cp /etc/letsencrypt/live/homelab.grenlan.com/*.pem /etc/traefik/certs/ && podman restart systemd-traefik"

# Rollback to previous certificate (last resort)
ssh pi@192.168.1.11 "sudo cp /etc/letsencrypt/archive/homelab.grenlan.com/*1.pem /etc/traefik/certs/"
```

### Database Emergency

**PostgreSQL Issues:**
```bash
# Check PostgreSQL status
ssh pi@192.168.1.13 "podman exec authentik_postgres pg_isready -U authentik"

# Check database connectivity
ssh pi@192.168.1.13 "podman exec authentik_postgres psql -U authentik -d authentik -c 'SELECT version();'"

# View database logs
ssh pi@192.168.1.13 "podman logs authentik_postgres | tail -50"

# Restart database (if safe)
ssh pi@192.168.1.13 "systemctl --user restart podman-authentik_postgres"
```

### SSH Access Recovery

**If Primary SSH Fails:**
1. **Tailscale SSH**: Use Tailscale SSH as backup (if configured)
2. **Physical Access**: Connect monitor/keyboard to Raspberry Pi
3. **Network Recovery**: Check if it's a network-wide issue

```bash
# Check SSH service status (via alternate method)
systemctl status ssh

# Check fail2ban status
sudo fail2ban-client status sshd

# Restart SSH service (last resort, use carefully)
sudo systemctl restart ssh
```

### Complete System Recovery

**Node-Level Recovery Process:**

1. **Identify Failed Node**:
```bash
ansible all -i ansible/inventories/prod/hosts.yml -m ping
```

2. **Access Alternate Node**:
```bash
# If pi-a fails, use pi-b for monitoring access
# If pi-b fails, use direct IP access to services
```

3. **Emergency Rollback**:
```bash
# Rollback to previous container images
git checkout HEAD~1 -- ansible/roles/[service]/defaults/main.yml
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/[service].yml --limit [failed_node]
```

4. **Canary Recovery**:
```bash
# Always test recovery on canary node first
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/[service].yml --limit pi-a
```

---

## Service Management

### Container Operations

**Standard Container Commands:**
```bash
# List all containers
ssh pi@[node_ip] "podman ps -a"

# View container logs
ssh pi@[node_ip] "podman logs [container_name]"

# Restart container
ssh pi@[node_ip] "systemctl --user restart podman-[container_name]"

# Check container health
ssh pi@[node_ip] "podman healthcheck run [container_name]"

# Container resource usage
ssh pi@[node_ip] "podman stats --no-stream"
```

**Service-Specific Operations:**

**Prometheus:**
```bash
# Check Prometheus targets
curl -s http://192.168.1.12:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up")'

# Prometheus configuration reload
ssh pi@192.168.1.12 "curl -X POST http://localhost:9090/-/reload"

# Check storage usage
ssh pi@192.168.1.12 "podman exec prometheus du -sh /prometheus"
```

**Grafana:**
```bash
# Reset admin password
ssh pi@192.168.1.12 "podman exec grafana grafana-cli admin reset-admin-password admin"

# Backup dashboards
ssh pi@192.168.1.12 "curl -H 'Content-Type: application/json' http://admin:admin@localhost:3000/api/search?type=dash-db"

# Database migration (if needed)
ssh pi@192.168.1.12 "podman exec grafana grafana-cli migrate-datasources"
```

**Authentik:**
```bash
# Check Authentik status
curl -sf http://192.168.1.13:9002/-/health/live/

# Database migration
ssh pi@192.168.1.13 "podman exec authentik manage migrate"

# Create superuser
ssh pi@192.168.1.13 "podman exec authentik manage createsuperuser"

# Clear cache
ssh pi@192.168.1.13 "podman exec authentik_redis redis-cli FLUSHALL"
```

**Traefik:**
```bash
# View Traefik configuration
curl -s http://192.168.1.11:8080/api/rawdata | jq .

# Check certificate status
curl -s http://192.168.1.11:8080/api/http/tls/certs | jq .

# Reload configuration
ssh pi@192.168.1.11 "systemctl --user restart podman-traefik"
```

### Configuration Management

**Ansible Playbook Execution:**
```bash
# Check syntax before execution
ansible-playbook --syntax-check ansible/playbooks/[playbook].yml

# Dry run (check mode)
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/[playbook].yml --check

# Execute on canary first
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/[playbook].yml --limit pi-a

# Full deployment (after canary success)
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/[playbook].yml
```

**Configuration Validation:**
```bash
# Validate Ansible inventory
ansible-inventory -i ansible/inventories/prod/hosts.yml --list

# Test Ansible connectivity
ansible all -i ansible/inventories/prod/hosts.yml -m ping

# Check for configuration drift
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/10-base.yml --check --diff
```

---

## Monitoring & Alerting

### Prometheus Queries

**Common Monitoring Queries:**
```promql
# Node resource usage
100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage percentage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Disk usage percentage
100 - ((node_filesystem_avail_bytes * 100) / node_filesystem_size_bytes)

# Container status
container_last_seen{name!=""}

# Service availability
up{job!=""}
```

**Alert Investigation:**
```bash
# Check active alerts
curl -s http://192.168.1.12:9090/api/v1/alerts | jq '.data.alerts[] | select(.state == "firing")'

# Query specific metric
curl -s "http://192.168.1.12:9090/api/v1/query?query=up" | jq .

# Check alert rules
curl -s http://192.168.1.12:9090/api/v1/rules | jq .
```

### Log Analysis

**Loki Query Examples:**
```logql
# Error logs in the last hour
{job="systemd"} |= "error" | logfmt

# Authentication failures
{job="authentik"} |= "failed" | logfmt

# Certificate renewal logs
{unit="certbot-renew.service"} | logfmt

# Container restart events
{job="systemd"} |= "podman" |= "restart" | logfmt
```

**Log Investigation Commands:**
```bash
# Query Loki directly
curl -G -s "http://192.168.1.12:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="systemd"} |= "error"' \
  --data-urlencode "start=$(date -d '1 hour ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000"

# Check Promtail status
ssh pi@192.168.1.12 "curl -s http://localhost:9080/ready"

# View Promtail logs
ssh pi@192.168.1.12 "podman logs promtail | tail -50"
```

### Performance Analysis

**Resource Trending:**
```bash
# CPU usage over time
curl -G -s "http://192.168.1.12:9090/api/v1/query_range" \
  --data-urlencode 'query=100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) by (instance) * 100)' \
  --data-urlencode 'start='$(date -d '24 hours ago' +%s) \
  --data-urlencode 'end='$(date +%s) \
  --data-urlencode 'step=3600'

# Network traffic patterns
curl -G -s "http://192.168.1.12:9090/api/v1/query" \
  --data-urlencode 'query=irate(node_network_receive_bytes_total{device!="lo"}[5m])'
```

---

## Backup & Recovery

### Automated Backups

**Daily Backup Verification:**
```bash
# Check backup status (when implemented)
ls -la /backup/daily/$(date +%Y%m%d)/

# Verify backup integrity
for backup in /backup/daily/$(date +%Y%m%d)/*.tar.gz; do
  tar -tzf "$backup" > /dev/null && echo "$backup: OK" || echo "$backup: CORRUPTED"
done
```

### Manual Backup Procedures

**Configuration Backup:**
```bash
# Backup entire Ansible configuration
tar -czf "homelab-config-$(date +%Y%m%d).tar.gz" ansible/ scripts/ quadlet/

# Backup Docker/Podman volumes
ssh pi@192.168.1.12 "podman volume export prometheus_data"
ssh pi@192.168.1.12 "podman volume export grafana_data"
```

**Database Backup:**
```bash
# PostgreSQL backup
ssh pi@192.168.1.13 "podman exec authentik_postgres pg_dump -U authentik authentik" > authentik-backup-$(date +%Y%m%d).sql

# Redis backup
ssh pi@192.168.1.13 "podman exec authentik_redis redis-cli BGSAVE"
ssh pi@192.168.1.13 "podman exec authentik_redis cp /data/dump.rdb /backup/"
```

**Certificate Backup:**
```bash
# Backup Let's Encrypt certificates
ssh pi@192.168.1.11 "sudo tar -czf letsencrypt-backup-$(date +%Y%m%d).tar.gz /etc/letsencrypt/"
```

### Recovery Procedures

**Service Recovery:**
```bash
# Restore from backup
scp backup-file.tar.gz pi@192.168.1.12:/tmp/
ssh pi@192.168.1.12 "cd /tmp && tar -xzf backup-file.tar.gz"

# Apply configuration
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/restore.yml --limit [target_node]
```

**Database Recovery:**
```bash
# PostgreSQL restore
ssh pi@192.168.1.13 "podman exec -i authentik_postgres psql -U authentik -d authentik" < authentik-backup.sql

# Redis restore
ssh pi@192.168.1.13 "podman cp dump.rdb authentik_redis:/data/"
ssh pi@192.168.1.13 "podman restart authentik_redis"
```

**Full Node Recovery:**
```bash
# Re-bootstrap node
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/00-bootstrap.yml --limit [failed_node]

# Apply full configuration
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  site.yml --limit [failed_node]

# Restore data from backups
# (Follow specific service recovery procedures)
```

---

## Troubleshooting Guides

### Common Issues

#### Issue: Service Not Responding

**Symptoms:**
- HTTP requests timeout or return connection refused
- Service not showing as "UP" in Prometheus

**Diagnosis:**
```bash
# Check container status
ssh pi@[node] "podman ps -a | grep [service]"

# Check systemd service
ssh pi@[node] "systemctl --user status podman-[service]"

# Check logs
ssh pi@[node] "podman logs [service] | tail -50"

# Check resource constraints
ssh pi@[node] "podman stats --no-stream [service]"
```

**Resolution:**
```bash
# Restart service
ssh pi@[node] "systemctl --user restart podman-[service]"

# If restart fails, check configuration
ssh pi@[node] "podman run --rm [image] --help"

# Re-deploy if configuration issue
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/[service].yml --limit [node]
```

#### Issue: High Resource Usage

**Symptoms:**
- High CPU or memory usage alerts
- System sluggish response

**Diagnosis:**
```bash
# Identify resource-heavy processes
ssh pi@[node] "htop" # Interactive
ssh pi@[node] "ps aux --sort=-%cpu | head -10"
ssh pi@[node] "ps aux --sort=-%mem | head -10"

# Check container resources
ssh pi@[node] "podman stats --no-stream"

# Disk usage check
ssh pi@[node] "df -h"
ssh pi@[node] "du -sh /var/lib/containers/*"
```

**Resolution:**
```bash
# Clean up old containers
ssh pi@[node] "podman system prune -f"

# Clean up old images
ssh pi@[node] "podman image prune -a -f"

# Check for log file growth
ssh pi@[node] "journalctl --disk-usage"
ssh pi@[node] "sudo journalctl --vacuum-time=7d"

# Scale resources if needed (in Quadlet files)
# Edit resource limits and redeploy
```

#### Issue: Network Connectivity Problems

**Symptoms:**
- Services can't communicate with each other
- External DNS resolution fails
- HTTPS access not working

**Diagnosis:**
```bash
# Check network interfaces
ssh pi@[node] "ip addr show"

# Check routing
ssh pi@[node] "ip route show"

# Test internal connectivity
ssh pi@192.168.1.12 "curl -sf http://192.168.1.13:5432"

# Check DNS resolution
ssh pi@[node] "dig homelab.grenlan.com"
ssh pi@[node] "nslookup time.cloudflare.com"

# Check firewall rules
ssh pi@[node] "sudo ufw status verbose"
```

**Resolution:**
```bash
# Reset network configuration
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/10-base.yml --limit [node] --tags network

# Check container network
ssh pi@[node] "podman network ls"
ssh pi@[node] "podman network inspect podman"

# Restart networking
ssh pi@[node] "sudo systemctl restart systemd-networkd"
```

#### Issue: Authentication Problems

**Symptoms:**
- Cannot login to Grafana via OAuth2
- Authentik returning errors
- ForwardAuth middleware blocking requests

**Diagnosis:**
```bash
# Check Authentik health
curl -sf http://192.168.1.13:9002/-/health/live/

# Check PostgreSQL connectivity
ssh pi@192.168.1.13 "podman exec authentik_postgres pg_isready -U authentik"

# Check Redis connectivity
ssh pi@192.168.1.13 "podman exec authentik_redis redis-cli ping"

# Test OAuth2 endpoints
curl -sf http://192.168.1.13:9002/application/o/token/
curl -sf http://192.168.1.13:9002/application/o/userinfo/
```

**Resolution:**
```bash
# Restart authentication stack
ssh pi@192.168.1.13 "systemctl --user restart podman-authentik*"
ssh pi@192.168.1.13 "systemctl --user restart podman-authentik_postgres"
ssh pi@192.168.1.13 "systemctl --user restart podman-authentik_redis"

# Clear authentication cache
ssh pi@192.168.1.13 "podman exec authentik_redis redis-cli FLUSHALL"

# Reset admin credentials
ssh pi@192.168.1.13 "podman exec authentik manage createsuperuser"
```

#### Issue: Certificate Problems

**Symptoms:**
- Browser shows certificate warnings
- HTTPS sites not accessible
- Certificate renewal failures

**Diagnosis:**
```bash
# Check certificate status
ssh pi@192.168.1.11 "sudo /opt/certbot-env/bin/certbot certificates"

# Check certificate files
ssh pi@192.168.1.11 "sudo ls -la /etc/letsencrypt/live/homelab.grenlan.com/"

# Test certificate renewal
ssh pi@192.168.1.11 "sudo /opt/certbot-env/bin/certbot renew --dry-run"

# Check Traefik certificate configuration
curl -s http://192.168.1.11:8080/api/http/tls/certs | jq .
```

**Resolution:**
```bash
# Force certificate renewal
ssh pi@192.168.1.11 "sudo /opt/certbot-env/bin/certbot renew --force-renewal"

# Copy certificates to Traefik
ssh pi@192.168.1.11 "sudo cp /etc/letsencrypt/live/homelab.grenlan.com/*.pem /etc/traefik/certs/"

# Restart Traefik
ssh pi@192.168.1.11 "podman restart systemd-traefik"

# If DNS issues, check Cloudflare API
ssh pi@192.168.1.11 "sudo cat /etc/letsencrypt/renewal/homelab.grenlan.com.conf"
```

### Performance Troubleshooting

#### Slow Response Times

**Investigation:**
```bash
# Check system load
ssh pi@[node] "uptime"

# Check I/O wait
ssh pi@[node] "iostat -x 1 5"

# Check network latency
ping -c 10 192.168.1.[node]

# Check service response times
time curl -sf http://192.168.1.12:3000/api/health
```

#### High Memory Usage

**Investigation:**
```bash
# Memory usage breakdown
ssh pi@[node] "free -h"
ssh pi@[node] "ps aux --sort=-%mem | head -10"

# Container memory usage
ssh pi@[node] "podman stats --no-stream --format 'table {{.Container}}\t{{.MemUsage}}\t{{.MemPerc}}'"

# Check for memory leaks
ssh pi@[node] "podman exec [container] cat /proc/meminfo"
```

---

## Maintenance Procedures

### Weekly Maintenance (15 minutes)

**System Updates:**
```bash
# Check for system updates (dry run)
ansible all -i ansible/inventories/prod/hosts.yml -m shell -a "sudo apt list --upgradable"

# Security updates only
ansible all -i ansible/inventories/prod/hosts.yml -m apt -a "upgrade=safe" --become

# Restart required services
ansible all -i ansible/inventories/prod/hosts.yml -m shell -a "sudo needrestart -r a"
```

**Log Maintenance:**
```bash
# Check log disk usage
ansible all -i ansible/inventories/prod/hosts.yml -m shell -a "journalctl --disk-usage"

# Clean old logs (keep 7 days)
ansible all -i ansible/inventories/prod/hosts.yml -m shell -a "sudo journalctl --vacuum-time=7d"

# Clean container logs
ansible all -i ansible/inventories/prod/hosts.yml -m shell -a "podman logs --since 24h [container] | tail -100"
```

**Certificate Monitoring:**
```bash
# Check certificate expiry
ssh pi@192.168.1.11 "sudo /opt/certbot-env/bin/certbot certificates"

# Test renewal process
ssh pi@192.168.1.11 "sudo /opt/certbot-env/bin/certbot renew --dry-run"
```

### Monthly Maintenance (30 minutes)

**Security Updates:**
```bash
# Full system update (test in staging first)
ansible all -i ansible/inventories/local/hosts.yml -m apt -a "upgrade=full" --become

# After staging validation, apply to production
ansible all -i ansible/inventories/prod/hosts.yml -m apt -a "upgrade=full" --become

# Reboot nodes if kernel updates installed (one at a time)
ansible pi-c -i ansible/inventories/prod/hosts.yml -m reboot --become
# Wait for services to come back up, then continue with other nodes
```

**Performance Review:**
```bash
# Generate performance report
curl -G -s "http://192.168.1.12:9090/api/v1/query" \
  --data-urlencode 'query=avg_over_time(node_cpu_seconds_total[30d])' | jq .

# Review resource usage trends in Grafana
# Check for any resource constraints or optimization opportunities
```

**Backup Verification:**
```bash
# Test backup restoration process
# (Execute on staging environment)
ansible-playbook -i ansible/inventories/local/hosts.yml \
  ansible/playbooks/test-restore.yml

# Verify backup integrity
find /backup -name "*.tar.gz" -exec tar -tzf {} \; > /dev/null
```

### Quarterly Maintenance (60 minutes)

**Infrastructure Review:**
```bash
# Review and update documentation
# Check CLAUDE.md compliance
# Update this runbook with lessons learned

# Security audit
ansible all -i ansible/inventories/prod/hosts.yml -m shell -a "sudo lynis audit system --quick"

# Performance benchmarking
ansible all -i ansible/inventories/prod/hosts.yml -m shell -a "sysbench cpu --cpu-max-prime=20000 run"
```

**Disaster Recovery Testing:**
```bash
# Test full node recovery procedure
# Document recovery time objectives (RTO) and recovery point objectives (RPO)
# Update disaster recovery procedures based on findings
```

---

## Change Management

### Pre-Deployment Checklist

**Before Any Production Change:**
- [ ] Change tested in local development environment
- [ ] Change tested in staging VMs  
- [ ] Time synchronization verified (< 100ms drift)
- [ ] SSH redundancy confirmed
- [ ] Canary deployment plan ready
- [ ] Rollback procedure identified
- [ ] Monitoring enabled for change impact
- [ ] Documentation updated

**Required Approvals:**
- [ ] Technical review completed
- [ ] Change window scheduled
- [ ] Stakeholders notified
- [ ] Rollback criteria defined

### Deployment Process

**Standard Deployment Workflow:**
```bash
# 1. Pre-flight checks
./scripts/preflight_time.sh
./scripts/preflight_ssh.sh

# 2. Canary deployment
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/[change].yml --limit pi-a

# 3. Canary validation
./scripts/verify_services.sh
# Manual testing of changed functionality

# 4. Full deployment (if canary successful)
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/[change].yml --limit production_full

# 5. Post-deployment validation
./scripts/verify_services.sh
# Comprehensive service testing
```

### Rollback Procedures

**Container Rollback:**
```bash
# Identify previous digest
git log --oneline -n 5 -- ansible/roles/[service]/defaults/main.yml

# Rollback to previous commit
git checkout [previous_commit] -- ansible/roles/[service]/defaults/main.yml

# Deploy rollback to canary first
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/[service].yml --limit pi-a

# If successful, rollback full deployment
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/[service].yml
```

**Configuration Rollback:**
```bash
# Use git to identify changes
git diff HEAD~1 ansible/

# Selective rollback
git checkout HEAD~1 -- ansible/[specific_file]

# Test and deploy rollback
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/[affected_playbook].yml --check

# Apply rollback
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/[affected_playbook].yml
```

### Emergency Changes

**For Critical Security Issues:**
```bash
# Emergency security patch deployment
# Skip staging if critical vulnerability

# Direct deployment with extra monitoring
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/security-patch.yml --limit pi-a

# Monitor closely for 15 minutes
watch './scripts/verify_services.sh'

# If stable, proceed with full deployment
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/security-patch.yml
```

---

## Contact Information

### Escalation Matrix

| Level | Contact | Scope | Response Time |
|-------|---------|-------|---------------|
| **L1 - Operations** | Operations Team | Service issues, routine maintenance | 1 hour |
| **L2 - Engineering** | Development Team | Configuration issues, deployments | 4 hours |
| **L3 - Architecture** | Platform Team | Design changes, security incidents | 8 hours |
| **L4 - Emergency** | On-call Engineer | Complete outage, security breach | 30 minutes |

### Key Resources

- **Documentation**: `/home/william/git/podman-homelab/docs/`
- **Configuration**: `/home/william/git/podman-homelab/ansible/`
- **Scripts**: `/home/william/git/podman-homelab/scripts/`
- **Monitoring**: `https://grafana.homelab.grenlan.com`
- **Repository**: Git repository with full history

### Emergency Contacts

- **Primary Access**: SSH keys for all production nodes
- **Backup Access**: Tailscale SSH (if configured)
- **Physical Access**: Direct console access to Raspberry Pi nodes
- **Network Access**: Router administration for network-level issues

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0.0 | 2025-08-15 | Initial runbook creation | Infrastructure Team |
| 1.1.0 | 2025-08-30 | Added authentication procedures | Infrastructure Team |
| 2.0.0 | 2025-09-04 | Complete rewrite with OAuth2 and Let's Encrypt | Infrastructure Team |

---

*This runbook is a living document and should be updated after any significant changes to the infrastructure or procedures. Regular review and testing of these procedures is essential for maintaining operational excellence.*

**Last Reviewed:** September 4, 2025  
**Next Review Due:** October 4, 2025  
**Document Status:** Current and Validated