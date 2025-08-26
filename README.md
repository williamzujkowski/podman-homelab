# Podman Homelab

A production-grade homelab infrastructure using Podman, Ansible, and GitHub CI/CD for managing a Raspberry Pi cluster.

## Overview

This repository implements a complete infrastructure-as-code solution for deploying and managing containerized services across a 3-node Raspberry Pi 5 cluster. The deployment pipeline follows a strict progression: **Local Development → VM Staging → Production Pis**.

### Key Features

- **Podman with Quadlet**: Systemd-native container management with digest-pinned images
- **Ansible Automation**: Idempotent configuration management with Molecule testing
- **GitHub CI/CD**: Environment-gated deployments with required approvals
- **Time Discipline**: Chrony with NTS (Cloudflare) + NIST servers, hard gates on drift
- **SSH Redundancy**: Dual access paths via OpenSSH and Tailscale SSH
- **Observability**: Prometheus, Grafana, Loki, and node_exporter
- **Security**: Unattended upgrades, UFW firewall, fail2ban, digest-pinned containers

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
│   │   └── ingress/        # Caddy/Traefik
│   └── playbooks/
│       ├── 00-bootstrap.yml
│       ├── 10-base.yml
│       ├── 20-podman.yml
│       ├── 30-observability.yml
│       └── 40-ingress.yml
├── quadlet/                # Systemd container units
├── scripts/
│   ├── preflight_time.sh  # Time sync verification
│   ├── preflight_ssh.sh   # SSH redundancy check
│   └── verify_services.sh # Service health checks
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

## Support

For issues or questions, please open a GitHub issue.

---

**Important**: This is production infrastructure. Always test in staging VMs before deploying to hardware. Never bypass the safety gates without understanding the risks.