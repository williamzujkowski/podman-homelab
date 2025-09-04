# Podman Homelab

A **production-deployed** homelab infrastructure using Podman, Ansible, Let's Encrypt, and GitHub CI/CD for managing a Raspberry Pi cluster with comprehensive authentication and monitoring.

**Status:** ✅ **PRODUCTION READY** - All core services operational with authentication framework deployed  
**Authentication:** ⚠️ OAuth2 setup requires manual configuration (15-20 minutes)

## Overview

This repository implements a complete infrastructure-as-code solution for deploying and managing containerized services across a 4-node Raspberry Pi 5 cluster with Cloudflare Origin CA certificates. The deployment pipeline follows a strict progression: **Local Development → VM Staging → Canary (pi-a) → Production Pis**.

### Key Features

- **Podman with Quadlet**: Systemd-native container management with digest-pinned images
- **Ansible Automation**: Idempotent configuration management with Molecule testing
- **GitHub CI/CD**: Environment-gated deployments with required approvals
- **Time Discipline**: Chrony with NTS (Cloudflare) + NIST servers, hard gates on drift
- **SSH Redundancy**: Dual access paths via OpenSSH and Tailscale SSH
- **Observability**: Prometheus, Grafana, Loki, and node_exporter
- **Security**: Cloudflare Origin CA (15-year certs), UFW firewall, internal-only access
- **Certificate Management**: Automated Let's Encrypt with Cloudflare DNS-01 challenge

### Production Infrastructure

| Node | IP | Role | Services | Status |
|------|-----|------|----------|--------|
| **pi-a** | 192.168.1.12 | Monitoring/Canary | Prometheus, Grafana, Loki, Promtail, Node Exporter | ✅ Operational |
| **pi-b** | 192.168.1.11 | Ingress | Traefik with Let's Encrypt, Node Exporter | ✅ Operational |
| **pi-c** | 192.168.1.10 | Worker | Node Exporter, Application services | ✅ Operational |
| **pi-d** | 192.168.1.13 | Storage/Auth | PostgreSQL, Redis, Authentik, MinIO (ready), Node Exporter | ✅ Operational |

## Access Services

### Direct Access (Internal Network Only)
- **Grafana**: http://192.168.1.12:3000 (admin/admin)
- **Prometheus**: http://192.168.1.12:9090
- **Loki**: http://192.168.1.12:3100
- **Authentik**: http://192.168.1.13:9002 (akadmin/vault_password)
- **Traefik Dashboard**: http://192.168.1.11:8080
- **PostgreSQL**: 192.168.1.13:5432 (database services)
- **Redis**: 192.168.1.13:6379 (cache and task queue)

### HTTPS Access via Let's Encrypt
Add to `/etc/hosts`:
```
192.168.1.11  homelab.grenlan.com grafana.homelab.grenlan.com prometheus.homelab.grenlan.com loki.homelab.grenlan.com auth.homelab.grenlan.com
```

Then access (Browser-trusted ✅):
- **Grafana**: https://grafana.homelab.grenlan.com (OAuth2 integration pending)
- **Prometheus**: https://prometheus.homelab.grenlan.com (monitoring metrics)
- **Loki**: https://loki.homelab.grenlan.com (log aggregation)  
- **Authentik**: https://auth.homelab.grenlan.com (identity management)

## Quick Start

### Prerequisites

- Ubuntu 24.04 host machine (for development)
- Python 3.11+
- Ansible 2.14+
- Podman 4.0+
- Multipass (for local VMs) or QEMU/KVM

### Local Development Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/yourusername/podman-homelab.git
   cd podman-homelab
   ```

2. **Install dependencies**:
   ```bash
   pip install ansible ansible-lint yamllint molecule molecule-podman
   ansible-galaxy collection install containers.podman community.general ansible.posix
   ```

3. **Create local VMs**:
   ```bash
   # Using Multipass (recommended)
   multipass launch 24.04 --name vm-a --cpus 2 --mem 4G --disk 30G
   multipass launch 24.04 --name vm-b --cpus 2 --mem 4G --disk 30G
   multipass launch 24.04 --name vm-c --cpus 2 --mem 4G --disk 30G
   ```

4. **Update inventory**:
   Edit `ansible/inventories/local/hosts.yml` with your VM IP addresses.

5. **Run bootstrap**:
   ```bash
   ansible-playbook -i ansible/inventories/local/hosts.yml \
     ansible/playbooks/00-bootstrap.yml
   ```

6. **Apply base configuration**:
   ```bash
   ansible-playbook -i ansible/inventories/local/hosts.yml \
     ansible/playbooks/10-base.yml
   ```

## Repository Structure

```
.
├── ansible/
│   ├── inventories/
│   │   ├── local/          # VM staging environment
│   │   └── prod/           # Production Pi cluster
│   ├── roles/
│   │   ├── base/           # Core system configuration
│   │   ├── podman/         # Container runtime setup
│   │   ├── monitoring/     # Prometheus stack
│   │   ├── logging/        # Loki + Promtail
│   │   ├── traefik/        # Traefik reverse proxy
│   │   ├── postgresql/     # PostgreSQL database
│   │   ├── authentik/      # Identity provider
│   │   └── lldap/          # LDAP directory
│   └── playbooks/
│       ├── 00-bootstrap.yml
│       ├── 10-base.yml
│       ├── 20-podman.yml
│       ├── 30-observability.yml
│       ├── 40-ingress.yml
│       ├── 50-authentik.yml
│       ├── 52-grafana-oauth2.yml
│       └── 60-grafana-dashboards.yml
├── docs/                   # Comprehensive documentation
│   ├── FINAL_DEPLOYMENT_REPORT.md
│   ├── DEPLOYMENT_STATUS.md
│   ├── OPERATIONAL_RUNBOOK.md
│   └── services/           # Service-specific documentation
├── scripts/
│   ├── preflight_time.sh   # Time sync verification
│   ├── preflight_ssh.sh    # SSH redundancy check
│   ├── verify_services.sh  # Service health checks
│   └── authentik-*         # OAuth2 configuration helpers
├── .github/workflows/
│   ├── ci.yml             # Lint and test
│   ├── deploy-staging.yml # VM deployment
│   └── deploy-prod.yml    # Pi deployment
└── renovate.json          # Dependency updates
```

## Deployment Pipeline

### Stage Gates

Each stage must pass before proceeding:

1. **M0**: Local repo & toolchain → lint/tests pass
2. **M1**: Local VMs up → time sync OK, SSH redundancy OK
3. **M2**: Base role → idempotent, chrony OK, unattended-upgrades enabled
4. **M3**: Podman + Quadlet → services healthy, auto-update verified
5. **M4**: Observability → Prometheus targets UP, logs flowing to Loki
6. **M5**: Ingress → routing to services working
7. **M6**: Vault + Keycloak → secrets management, SSO (optional)
8. **M7**: GitHub CI/CD → pipelines green, environment approvals wired
9. **M8**: Canary Pi → single Pi deployment successful
10. **M9**: Full rollout → all Pis deployed

### GitHub Environments

- **staging**: Auto-deploys to VMs on main branch push
- **production**: Requires manual approval, canary deployment first
- **production-full**: Requires second approval for full cluster rollout

## Operational Guidelines

### Preflight Checks

Always run before deployments:

```bash
# Time synchronization check
./scripts/preflight_time.sh

# SSH redundancy verification
./scripts/preflight_ssh.sh <hostname>
```

### Container Management

All containers use Quadlet with digest-pinned images:

```ini
# Example: quadlet/prometheus.container
[Container]
Image=docker.io/prom/prometheus:v2.48.0@sha256:abc123...
Volume=/etc/prometheus:/etc/prometheus:ro
PublishPort=9090:9090
HealthCmd=/bin/promtool check ready

[Service]
Restart=always

[Install]
WantedBy=default.target
```

### Rollback Strategy

1. **Containers**: Revert to previous digest in Git, re-apply to canary first
2. **Config**: Use `serial: 1` in Ansible, keep previous state files
3. **SSH**: If OpenSSH fails, use Tailscale SSH for recovery

## Security Considerations

- **Time Gates**: Deployments abort if drift >100ms or stratum >3
- **SSH Redundancy**: Never modify both SSH methods in one change
- **Container Digests**: All images pinned to specific digests
- **Automated Updates**: Security patches via unattended-upgrades
- **Network Security**: UFW firewall with minimal exposed ports

## Testing

Run the test suite locally:

```bash
# Linting
yamllint .
ansible-lint

# Molecule tests (per role)
cd ansible/roles/base
molecule test

# Shellcheck
shellcheck scripts/*.sh
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes with appropriate tests
4. Ensure all CI checks pass
5. Open a PR with clear description

## License

MIT

## Documentation

### Quick Reference
- **[FINAL_DEPLOYMENT_REPORT.md](docs/FINAL_DEPLOYMENT_REPORT.md)**: Comprehensive infrastructure status and configuration guide
- **[DEPLOYMENT_STATUS.md](docs/DEPLOYMENT_STATUS.md)**: Current service status and access information  
- **[OPERATIONAL_RUNBOOK.md](docs/operations/OPERATIONAL_RUNBOOK.md)**: Daily operations, troubleshooting, and maintenance procedures
- **[CLAUDE.md](CLAUDE.md)**: Operational playbook and golden rules (MUST READ)

### Service Documentation
- **[OAuth2 Integration](docs/services/AUTHENTIK_OAUTH2_INTEGRATION_REPORT.md)**: Authentik and Grafana SSO setup
- **[Cloudflare Integration](docs/services/CLOUDFLARE_INTEGRATION.md)**: Certificate and DNS configuration
- **[Authentik Configuration](docs/services/AUTHENTIK_CONFIGURATION_REPORT.md)**: Identity provider setup

### Next Steps
1. **Complete OAuth2 Setup** (15-20 minutes):
   ```bash
   ./scripts/authentik-manual-config-guide.sh
   ```
2. **Test Authentication Flow**:
   ```bash
   python3 scripts/test-oauth2-flow.py
   ```
3. **Deploy Additional Services**: MinIO, LLDAP, custom applications

## Support

- **Repository**: Complete infrastructure-as-code with full documentation
- **Issues**: Open GitHub Issues for bugs and feature requests  
- **Security**: Use GitHub Security Advisories for security issues
- **Operations**: Follow procedures in OPERATIONAL_RUNBOOK.md

---

**Important**: This is production infrastructure. Always test in staging VMs before deploying to hardware. Never bypass the safety gates without understanding the risks.