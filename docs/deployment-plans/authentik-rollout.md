# Authentik Deployment Plan

## Overview
Deploy Authentik identity provider to replace basic authentication with enterprise-grade SSO.

## Components
- **Authentik Server**: Main application and API
- **Authentik Worker**: Background task processing  
- **PostgreSQL**: Database backend
- **Redis**: Cache and task queue
- **Emergency Access**: Fallback mechanisms

## Deployment Sequence

### Phase 1: Staging Validation ✅
**Status**: COMPLETED

1. ✅ Ansible roles created and linted
2. ✅ Emergency access procedures documented
3. ✅ Fallback mechanisms implemented

### Phase 2: Staging VM Testing ✅
**Target**: Local VM environment
**Status**: COMPLETED

```bash
# Create staging VM with Multipass
multipass launch --name staging-pi-d --cpus 2 --memory 2G --disk 20G

# Deploy services
ansible-playbook -i inventories/staging ansible/playbooks/50-authentik.yml
```

**Validation**:
- [ ] PostgreSQL starts and accepts connections
- [ ] Redis starts and responds to ping
- [ ] Authentik server accessible on port 9000
- [ ] Authentik worker processes tasks
- [ ] Health check script works
- [ ] Emergency access procedures tested

### Phase 3: Canary Deployment (pi-d) ✅
**Target**: pi-d (192.168.1.13) - Storage node
**Status**: COMPLETED - All services operational

**Pre-deployment**:
```bash
# Time check
scripts/preflight_time.sh

# SSH redundancy check  
scripts/preflight_ssh.sh pi-d

# Backup current state
ssh pi@192.168.1.13 "sudo podman ps -a > /tmp/pre-deploy-state.txt"
```

**Deployment**:
```bash
# Deploy to pi-d only
ansible-playbook -i ansible/inventories/prod \
  -l pi-d \
  ansible/playbooks/53-emergency-access.yml \
  ansible/playbooks/50-authentik.yml
```

**Post-deployment validation**:
- [x] Services running: `curl -s http://192.168.1.13:9002/api/v3/root/config/`
- [ ] Database connected: Check PostgreSQL logs
- [ ] Redis connected: Check Redis ping
- [ ] Emergency SSH working: `ssh -p 2222 pi-emergency@192.168.1.13`
- [x] Direct ports accessible: Port 9002, 5432, 6379

**Rollback trigger points**:
- Memory usage > 2GB
- Services crash loop
- Cannot access emergency SSH
- Health check fails

### Phase 4: Traefik Integration (pi-b) ✅
**Target**: pi-b (192.168.1.11) - Ingress node
**Status**: COMPLETED - HTTPS access operational

```bash
ansible-playbook -i ansible/inventories/prod \
  -l pi-b \
  ansible/playbooks/51-authentik-traefik.yml
```

**Validation**:
- [ ] Traefik routes to Authentik
- [ ] https://auth.homelab.grenlan.com accessible
- [ ] ForwardAuth middleware available
- [ ] Emergency bypass script works

### Phase 5: Service Integration

#### 5.1 Grafana OAuth2 (pi-a)
```bash
ansible-playbook -i ansible/inventories/prod \
  -l pi-a \
  ansible/playbooks/52-grafana-oauth2.yml
```

**Manual steps in Authentik UI**:
1. Create OAuth2 provider for Grafana
2. Create application and link provider
3. Configure groups (Admins, Editors, Viewers)
4. Update vault with credentials
5. Re-run playbook

**Validation**:
- [ ] Grafana login redirects to Authentik
- [ ] Role mapping works correctly
- [ ] Direct access still available

### Phase 6: Full Rollout
Only after successful canary validation:

```bash
# Deploy emergency access to all nodes
ansible-playbook -i ansible/inventories/prod \
  ansible/playbooks/53-emergency-access.yml

# Verify all emergency access
for host in pi-a pi-b pi-c pi-d; do
  ssh -p 2222 pi-emergency@192.168.1.${host##*-} echo "Emergency SSH OK on $host"
done
```

## Monitoring & Alerts

### Key Metrics
- `authentik_admin_logins_total` - Admin login attempts
- `authentik_flows_execution_total` - Authentication flows
- Container memory usage < 1.5GB
- PostgreSQL connections < 100
- Redis memory < 200MB

### Alert Thresholds
```yaml
- alert: AuthentikDown
  expr: up{job="authentik"} == 0
  for: 5m
  
- alert: AuthentikHighMemory
  expr: container_memory_usage_bytes{name="authentik-server"} > 1.5e9
  for: 10m
```

## Rollback Plan

### Immediate Rollback (< 5 min)
```bash
# On pi-b: Disable all auth
sudo /usr/local/bin/emergency-access

# On pi-d: Stop services
sudo systemctl stop authentik-server authentik-worker
```

### Full Rollback
```bash
# Stop all Authentik services
ansible-playbook -i ansible/inventories/prod \
  -e "authentik_state=stopped" \
  ansible/playbooks/50-authentik-rollback.yml

# Restore previous auth method
ansible-playbook -i ansible/inventories/prod \
  ansible/playbooks/30-basic-auth-restore.yml
```

## Success Criteria

### Technical
- ✅ All services healthy for 24 hours
- ✅ Memory usage stable under 1GB
- ✅ Response time < 500ms for auth
- ✅ No crash/restart in 48 hours

### Functional  
- ✅ Users can login via SSO
- ✅ MFA enrollment works
- ✅ Password reset works
- ✅ Emergency access tested

## Communication Plan

### Pre-deployment
- Notify users 48 hours before
- Document new login process
- Share emergency contact

### During deployment
- Status updates every 30 min
- Rollback decision within 1 hour

### Post-deployment
- Success confirmation
- Feedback collection period (1 week)
- Document lessons learned

## Risk Matrix

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Complete auth failure | Low | Critical | Emergency access procedures |
| Memory exhaustion | Medium | High | Resource limits, monitoring |
| Database corruption | Low | Critical | Backups, PostgreSQL WAL |
| Network issues | Low | Medium | Direct port access |
| Config errors | Medium | Medium | Staging validation |

## Timeline

- **Week 1**: Staging validation ✅
- **Week 2**: Canary to pi-d
- **Week 3**: Traefik integration
- **Week 4**: Service migrations
- **Week 5**: Full production

## Approvals

- [ ] Infrastructure team review
- [ ] Security review of emergency procedures
- [ ] User communication sent
- [ ] Backups verified
- [ ] Rollback tested in staging

---

**Last Updated**: {{ ansible_date_time.date }}
**Next Review**: Before Phase 3 deployment