# Authentik Identity Provider

## Overview

Authentik is a comprehensive identity provider (IdP) that supports modern authentication protocols including OAuth2/OIDC, SAML, LDAP, and forward auth. It provides single sign-on (SSO) capabilities for the entire homelab infrastructure.

## Architecture

Authentik consists of:
- **Server**: Web interface and API
- **Worker**: Background task processing
- **PostgreSQL**: Primary database
- **Redis**: Cache and task queue

## Deployment

Authentik is deployed on **pi-d** (192.168.1.13) - the storage node with sufficient resources.

### Resource Requirements
- **RAM**: ~1GB (server: 1024MB, worker: 512MB, Redis: 256MB)
- **CPU**: ~2 cores total
- **Storage**: ~500MB for application + database growth

### Ports
- `9002`: HTTP (internal API and web interface)
- `9443`: HTTPS (optional, we use Traefik instead)
- `9300`: Metrics (Prometheus)

## Access URLs

- **External**: https://auth.homelab.grenlan.com (via Traefik on pi-b)
- **Internal**: http://192.168.1.13:9002
- **API**: https://auth.homelab.grenlan.com/api/v3/

## Default Credentials

- **Username**: akadmin
- **Password**: Set in vault as `vault_authentik_admin_password`
- **Email**: admin@homelab.grenlan.com

⚠️ **IMPORTANT**: Change the default password immediately after first login!

## Configuration

### Environment Variables

Key configuration stored in `/etc/authentik/authentik.env`:
- `AUTHENTIK_SECRET_KEY`: 50-character random string
- `AUTHENTIK_POSTGRESQL__*`: Database connection
- `AUTHENTIK_REDIS__*`: Redis connection
- `AUTHENTIK_EXTERNAL_URL`: Public URL for OAuth2/SAML

### Traefik Integration

Traefik on pi-b provides:
1. **Reverse Proxy**: Routes auth.homelab.grenlan.com to Authentik
2. **ForwardAuth**: Protects services with `authentik-auth` middleware
3. **TLS Termination**: Let's Encrypt certificates

Protected services add this label:
```yaml
traefik.http.routers.service.middlewares: authentik-auth@file
```

### Grafana OAuth2 Integration

1. Create OAuth2 provider in Authentik:
   - Type: OAuth2/OpenID Provider
   - Client ID: grafana
   - Redirect URI: https://grafana.homelab.grenlan.com/login/generic_oauth

2. Create application:
   - Name: Grafana
   - Provider: (link to OAuth2 provider)

3. Configure groups for role mapping:
   - `Grafana Admins` → Admin role
   - `Grafana Editors` → Editor role
   - Default → Viewer role

## Service Management

### Health Check
```bash
sudo /usr/local/bin/check-authentik-health
```

### Container Management
```bash
# Status
sudo systemctl status authentik-server
sudo systemctl status authentik-worker

# Logs
sudo podman logs authentik-server
sudo podman logs authentik-worker

# Restart
sudo systemctl restart authentik-server authentik-worker
```

### Database Access
```bash
# Connect to PostgreSQL
sudo podman exec -it postgresql psql -U authentik -d authentik

# Connect to Redis
sudo podman exec -it redis redis-cli
```

## Backup and Recovery

### Database Backup
```bash
# Manual backup
sudo podman exec postgresql pg_dump -U authentik authentik > /backup/authentik-$(date +%Y%m%d).sql

# Restore
sudo podman exec -i postgresql psql -U authentik authentik < /backup/authentik-20240101.sql
```

### Media Files
Media files stored in `/var/lib/authentik/media` should be included in regular backups.

## Monitoring

### Metrics
Prometheus metrics available at: http://192.168.1.13:9300/metrics

Key metrics to monitor:
- `authentik_admin_logins_total`: Admin login attempts
- `authentik_flows_execution_total`: Flow executions
- `authentik_policies_execution_total`: Policy evaluations
- `authentik_provider_authorization_total`: OAuth2 authorizations

### Alerts
Configure Prometheus alerts for:
- Container health failures
- High memory usage (>900MB)
- Database connection failures
- Redis connection failures

## Security Considerations

1. **Secret Key**: Generate unique 50+ character key
2. **Database Passwords**: Use strong, unique passwords
3. **Network Isolation**: Containers use internal network
4. **TLS**: Always access via HTTPS in production
5. **Token Rotation**: Regularly rotate OAuth2 tokens
6. **Audit Logs**: Review authentication logs regularly

## Troubleshooting

### Common Issues

1. **Cannot access web interface**
   - Check container status: `sudo systemctl status authentik-server`
   - Verify network: `curl http://localhost:9002/api/v3/root/config/`
   - Check logs: `sudo podman logs authentik-server`

2. **Worker not processing tasks**
   - Check Redis connection: `sudo podman exec redis redis-cli ping`
   - Restart worker: `sudo systemctl restart authentik-worker`

3. **Database connection failed**
   - Verify PostgreSQL running: `sudo systemctl status postgresql`
   - Check credentials in `/etc/authentik/authentik.env`

4. **OAuth2 redirect issues**
   - Verify `AUTHENTIK_EXTERNAL_URL` matches public URL
   - Check redirect URIs in provider configuration
   - Ensure Traefik headers are forwarded

### Debug Mode
Enable debug logging by setting in `/etc/authentik/authentik.env`:
```bash
AUTHENTIK_LOG_LEVEL=debug
```

Then restart services:
```bash
sudo systemctl restart authentik-server authentik-worker
```

## Integration Examples

### Protecting a Service with ForwardAuth

Add to service's Traefik labels:
```yaml
traefik.http.routers.myservice.middlewares: authentik-auth@file
```

### Creating an OAuth2 Application

1. Navigate to Providers → Create
2. Select OAuth2/OpenID Provider
3. Configure:
   - Client ID: myapp
   - Client Secret: (generate)
   - Redirect URIs: https://myapp.homelab.grenlan.com/callback
4. Create Application and link to provider
5. Assign to users/groups

### LDAP Outpost (Optional)

For legacy applications requiring LDAP:
1. Create LDAP Provider in Authentik
2. Deploy LDAP Outpost container
3. Configure service to use `ldap://192.168.1.13:389`

## Maintenance

### Updates
```bash
# Update container image
sudo sed -i 's/authentik_version: .*/authentik_version: "2024.10.0"/' /etc/ansible/group_vars/all.yml
ansible-playbook ansible/playbooks/50-authentik.yml

# Apply migrations
sudo podman exec authentik-server /lifecycle/ak migrate
```

### Performance Tuning
- Increase worker processes for high load
- Add Redis persistence for cache survival
- Use PostgreSQL connection pooling
- Enable GeoIP for location tracking

## Emergency Access Procedures

### Critical: Fallback Access Methods

To prevent complete lockout, multiple access methods are maintained:

1. **Direct SSH** (Always Independent of Authentik)
   - Port 22: Standard SSH with key auth
   - Port 2222: Emergency SSH backup
   - User: `pi` (standard) or `pi-emergency` (backup)
   
2. **Direct Service Access** (Bypasses Traefik/Authentik)
   ```bash
   # Critical services remain accessible
   http://192.168.1.12:9090  # Prometheus
   http://192.168.1.12:3000  # Grafana
   http://192.168.1.13:9002  # Authentik admin
   ```

3. **Emergency Bypass Scripts** (on pi-b)
   ```bash
   # Disable all Authentik authentication
   sudo /usr/local/bin/emergency-access
   
   # Restore normal authentication
   sudo /usr/local/bin/restore-auth
   ```

### Recovery Procedure

1. **Access via SSH** (never depends on Authentik)
   ```bash
   ssh pi@192.168.1.13  # Direct to pi-d where Authentik runs
   ```

2. **Check Service Status**
   ```bash
   sudo systemctl status authentik-server authentik-worker
   sudo podman ps -a | grep authentik
   ```

3. **Review Logs**
   ```bash
   sudo podman logs authentik-server --tail 50
   sudo podman logs authentik-worker --tail 50
   ```

4. **Restart if Needed**
   ```bash
   sudo systemctl restart authentik-server authentik-worker
   ```

5. **If Authentik Cannot be Fixed**
   - SSH to pi-b: `ssh pi@192.168.1.11`
   - Run: `sudo /usr/local/bin/emergency-access`
   - This disables ForwardAuth globally
   - Fix Authentik
   - Run: `sudo /usr/local/bin/restore-auth`

### Important Safety Rules

1. **Never** require Authentik for SSH access
2. **Always** maintain direct port access to critical services
3. **Test** emergency procedures quarterly
4. **Document** all emergency access usage
5. **Keep** emergency credentials in secure vault

## References

- [Official Documentation](https://goauthentik.io/docs/)
- [API Reference](https://goauthentik.io/api/)
- [Integration Guides](https://goauthentik.io/integrations/)