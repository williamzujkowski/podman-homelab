# Authentik ForwardAuth Configuration Guide

This guide walks through configuring Authentik to provide ForwardAuth authentication for Traefik.

## Current Status

- **Authentik Server**: Running at http://192.168.1.13:9002 (container unhealthy but responding)
- **Authentik Worker**: Running (healthy)
- **Database**: PostgreSQL running (healthy)
- **Cache**: Redis running (healthy)
- **ForwardAuth Endpoint**: Not yet configured (returns 404)

## Configuration Steps

### Step 1: Complete Initial Setup

1. **Access Authentik Setup**:
   ```bash
   # Open in browser:
   http://192.168.1.13:9002/if/flow/initial-setup/
   ```

2. **Create Admin User**:
   - Username: `akadmin`
   - Name: `authentik Default Admin`
   - Email: `admin@homelab.grenlan.com`
   - Password: `ChangeMe123!`
   - Confirm Password: `ChangeMe123!`

3. **Click "Create"** to complete initial setup

### Step 2: Create Traefik Proxy Provider

1. **Access Admin Interface**:
   ```bash
   # Open in browser:
   http://192.168.1.13:9002
   ```

2. **Login**:
   - Username: `akadmin`
   - Password: `ChangeMe123!`

3. **Navigate to Providers**:
   - Go to: Applications → Providers
   - Click: "Create"

4. **Select Provider Type**:
   - Choose: "Proxy Provider"

5. **Configure Provider**:
   ```
   Name: traefik-forwardauth
   Authorization flow: default-provider-authorization-explicit-consent
   Mode: Forward auth (single application)
   External host: https://auth.homelab.grenlan.com
   Internal host: http://192.168.1.13:9002
   Internal host SSL Validation: ✓ (checked)
   Token validity: hours=24
   Cookie domain: homelab.grenlan.com
   ```

6. **Save Provider**

### Step 3: Configure Embedded Outpost

1. **Navigate to Outposts**:
   - Go to: Applications → Outposts

2. **Edit Embedded Outpost**:
   - Find: "authentik Embedded Outpost"
   - Click: "Edit" (pencil icon)

3. **Add Provider**:
   - In "Selected providers" section
   - Find and select: "traefik-forwardauth"
   - Click: "Update"

4. **Wait for Outpost Restart**:
   - The outpost will automatically restart
   - This may take 30-60 seconds

### Step 4: Verify Configuration

1. **Test ForwardAuth Endpoint**:
   ```bash
   curl -I http://192.168.1.13:9002/outpost.goauthentik.io/auth/traefik
   ```
   
   **Expected Response**: HTTP 302 (redirect) or HTTP 200 (OK)

2. **Run Verification Script**:
   ```bash
   /home/william/git/podman-homelab/scripts/configure-authentik-forwardauth.sh
   ```

## Troubleshooting

### ForwardAuth Returns 404

**Symptoms**:
```bash
curl http://192.168.1.13:9002/outpost.goauthentik.io/auth/traefik
# Returns: HTTP 404
```

**Solutions**:
1. Verify proxy provider is created correctly
2. Ensure outpost includes the provider
3. Wait for outpost to restart (check logs)
4. Restart Authentik containers if needed

### Container Health Issues

**Check Container Status**:
```bash
ssh pi@192.168.1.13 "sudo podman ps"
```

**View Logs**:
```bash
ssh pi@192.168.1.13 "sudo podman logs authentik-server --tail 50"
ssh pi@192.168.1.13 "sudo podman logs authentik-worker --tail 50"
```

**Restart Containers**:
```bash
ssh pi@192.168.1.13 "sudo systemctl --user restart authentik-server"
ssh pi@192.168.1.13 "sudo systemctl --user restart authentik-worker"
```

### Authentication Issues

**Reset Admin Password** (if needed):
```bash
ssh pi@192.168.1.13 "sudo podman exec authentik-server python manage.py changepassword akadmin"
```

## Integration with Traefik

The Traefik middleware is already configured in `/ansible/roles/traefik/files/authentik.yml`:

```yaml
http:
  middlewares:
    authentik-auth:
      forwardAuth:
        address: "http://192.168.1.13:9002/outpost.goauthentik.io/auth/traefik"
        trustForwardHeader: true
        authResponseHeaders:
          - X-authentik-username
          - X-authentik-groups
          - X-authentik-email
          # ... (other headers)
```

To protect a service with Authentik:
```yaml
http:
  routers:
    protected-service:
      rule: "Host(`service.homelab.grenlan.com`)"
      middlewares:
        - authentik-auth@file  # Apply ForwardAuth
      service: my-service
```

## Testing Authentication

1. **Access Protected Service**: Navigate to a protected service URL
2. **Expect Redirect**: Should redirect to `https://auth.homelab.grenlan.com`
3. **Login**: Use akadmin credentials
4. **Grant Access**: If prompted, authorize the application
5. **Access Granted**: Should redirect back to the service

## API Configuration (Advanced)

For programmatic configuration, see:
- `/home/william/git/podman-homelab/scripts/authentik-api-config.py`
- `/home/william/git/podman-homelab/scripts/configure-authentik-forwardauth.py`

## Next Steps

After ForwardAuth is working:

1. **Create Applications**: Define specific applications in Authentik
2. **Configure Flows**: Customize authentication and authorization flows  
3. **Set Up LDAP**: Integrate with LLDAP for user management
4. **Configure Groups**: Set up user groups and permissions
5. **Enable MFA**: Add multi-factor authentication

## Security Notes

- Change the default password immediately after setup
- Consider using a more secure admin email domain
- Review and customize authorization flows
- Enable audit logging for security events
- Regularly update Authentik to the latest version

## Configuration Files

Key configuration files in this repository:
- `ansible/roles/authentik/templates/authentik-server.container.j2`
- `ansible/roles/authentik/templates/authentik.env.j2`
- `ansible/roles/traefik/files/authentik.yml`
- `ansible/playbooks/50-authentik.yml`