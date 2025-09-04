# Authentik-Traefik ForwardAuth Integration

## Overview

This document describes the integration between Authentik (identity provider) and Traefik (reverse proxy) using the ForwardAuth middleware to provide authentication for services in the homelab environment.

## Architecture

- **Authentik**: Running on pi-d (192.168.1.13:9002) - Identity Provider
- **Traefik**: Running on pi-b (192.168.1.11) - Reverse Proxy with ForwardAuth middleware
- **Integration**: ForwardAuth middleware directs authentication requests to Authentik

## Deployment Status

✅ **Authentik Deployed**: Running on pi-d port 9002 (resolves MinIO port conflict)
✅ **Traefik Configuration**: ForwardAuth middleware deployed to `/etc/traefik/dynamic/authentik.yml`
✅ **Middleware Loaded**: `authentik-auth@file` middleware active in Traefik
✅ **Routers Configured**: `authentik@file` and `authentik-outpost@file` routes active
⚠️ **Network Connectivity**: Issue identified between pi-b and pi-d (firewall/routing)

## Configuration Files

### 1. Authentik Configuration
**Location**: `/home/william/git/podman-homelab/ansible/roles/authentik/defaults/main.yml`
```yaml
# Modified ports to avoid MinIO conflict
authentik_http_port: 9002
authentik_https_port: 9003
authentik_metrics_port: 9300
```

### 2. Traefik Dynamic Configuration
**Location**: `/etc/traefik/dynamic/authentik.yml` on pi-b
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
          - X-authentik-name
          - X-authentik-uid
          - X-authentik-jwt

  routers:
    authentik-homelab:
      rule: "Host(`auth.homelab.grenlan.com`)"
      service: authentik
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

  services:
    authentik:
      loadBalancer:
        servers:
          - url: "http://192.168.1.13:9002"
        healthCheck:
          path: /api/v3/root/config/
          interval: 30s
          timeout: 3s
```

## Usage Instructions

### Protecting a Service with Authentication

To protect any service with Authentik authentication, add the ForwardAuth middleware to its router:

```yaml
http:
  routers:
    protected-service:
      rule: "Host(`service.homelab.grenlan.com`)"
      service: your-service
      middlewares:
        - authentik-auth  # This enforces authentication
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt
```

### Available Middlewares

- **`authentik-auth`**: Enforces authentication (redirects to login if not authenticated)
- **`authentik-auth-optional`**: Optional authentication (passes through if authenticated, allows unauthenticated access)

### Authentication Headers

When a user is authenticated, Traefik forwards these headers to your services:
- `X-authentik-username`: User's username
- `X-authentik-groups`: User's group memberships
- `X-authentik-email`: User's email address
- `X-authentik-name`: User's display name
- `X-authentik-uid`: User's unique identifier
- `X-authentik-jwt`: JWT token for the session

## Access Information

### Service URLs
- **Authentik Admin**: https://auth.homelab.grenlan.com (once connectivity is resolved)
- **Authentik Internal**: http://192.168.1.13:9002
- **Traefik Dashboard**: http://192.168.1.11:8080

### Default Credentials
- **Username**: akadmin
- **Password**: ChangeMe123! (configured in vault_authentik_bootstrap_password)

## Testing the Setup

### 1. Verify Authentik is Running
```bash
ssh pi@192.168.1.13 "curl -I http://localhost:9002/api/v3/root/config/"
```

### 2. Check Traefik Middleware
```bash
ssh pi@192.168.1.11 "curl -s http://localhost:8080/api/http/middlewares | grep authentik"
```

### 3. Test Protected Service
1. Apply `authentik-auth` middleware to a service
2. Access the service URL
3. Should redirect to Authentik login page
4. After authentication, should forward to original service

## Known Issues and Troubleshooting

### Network Connectivity Issue
**Problem**: Traefik on pi-b cannot reach Authentik on pi-d (port 9002)
**Symptoms**: 504 Gateway Timeout when accessing auth.homelab.grenlan.com
**Status**: Under investigation

**Current Findings**:
- Authentik responds correctly on pi-d localhost
- Port 9002 is open in ufw firewall
- Basic ping works between nodes
- TCP connections timeout (telnet, curl)

**Potential Causes**:
- iptables DROP policy on pi-d INPUT chain
- Podman/Container network isolation
- Network routing configuration

**Workarounds**:
1. Access Authentik directly via http://192.168.1.13:9002 for configuration
2. Temporarily test ForwardAuth by moving Authentik to pi-b or resolving network connectivity

### Debug Commands
```bash
# Test basic connectivity
ssh pi@192.168.1.11 "ping -c 2 192.168.1.13"

# Check port accessibility
ssh pi@192.168.1.11 "nc -zv 192.168.1.13 9002"

# Check iptables rules
ssh pi@192.168.1.13 "sudo iptables -L -n | grep 9002"

# Check listening ports
ssh pi@192.168.1.13 "sudo ss -tlnp | grep :9002"

# Check Traefik logs
ssh pi@192.168.1.11 "podman logs systemd-traefik | tail -20"
```

## Next Steps

1. **Resolve Network Connectivity**: Debug and fix the network issue between pi-b and pi-d
2. **Configure Authentik**: Set up applications, providers, and outposts in Authentik admin interface
3. **Test Authentication Flow**: Verify full end-to-end authentication works
4. **Apply to Services**: Add ForwardAuth middleware to protect existing services
5. **Documentation**: Update service-specific documentation with authentication requirements

## Deployment History

- **2025-09-04**: Initial deployment with port conflict resolution (9002/9003)
- **Network Issue**: Identified connectivity problem between Traefik and Authentik
- **Configuration Status**: ForwardAuth middleware properly deployed and loaded

## Related Files

- `/home/william/git/podman-homelab/ansible/playbooks/50-authentik.yml` - Authentik deployment
- `/home/william/git/podman-homelab/ansible/playbooks/51-authentik-traefik.yml` - Traefik integration
- `/home/william/git/podman-homelab/ansible/roles/authentik/` - Authentik role
- `/home/william/git/podman-homelab/ansible/roles/traefik/` - Traefik role