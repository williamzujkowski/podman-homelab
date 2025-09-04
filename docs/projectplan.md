# **PROJECTPLAN.md**

**Owner:** William
**Last updated:** *(set on first commit)*
**Initial hardware target:** 3× Raspberry Pi 5 (16 GB) + 3× 1 TB SSDs
**Design goal:** Build everything **locally first** (laptop) → **VM “staging”** → **Pi “prod”**, with GitHub CI/CD, strong safety rails (time sync, SSH redundancy), and deterministic rollbacks.

---

## 0) Objectives (no-nonsense)

* **Local-first**: Stand up the entire stack on your laptop using **Ubuntu VMs** (Multipass or QEMU/KVM). Only after everything passes tests + approvals do we touch hardware. ([Ubuntu Documentation][1])
* **Runtime**: **Podman** with **Quadlet** (systemd units); selective **auto-update** with labels + timer. ([docs.podman.io][2])
* **IaC**: **Ansible** + `containers.podman` collection; roles tested with **Molecule (Podman)**. ([Ansible][3], [ansible.readthedocs.io][4])
* **Time discipline**: **chrony** with **Cloudflare NTS** (`time.cloudflare.com`) plus **NIST** ITS servers; deployments abort if drift >100 ms or stratum >3. ([Cloudflare Docs][5], [Cloudflare][6], [NIST][7], [NIST][8])
* **SSH never-lock-out**: Two independent doors at all times—**OpenSSH** and **Tailscale SSH** (doesn’t edit `sshd_config`, assumes port 22). ([Tailscale][9])
* **Observability**: **Prometheus + node\_exporter**, **Grafana**, and **Loki + Promtail (journald)**. ([Prometheus][10], [GitHub][11], [Grafana Labs][12])
* **Secrets & SSO**: **HashiCorp Vault** for secrets; **Keycloak** for OIDC SSO (optional in phase 2).
* **Updates**: Ubuntu **unattended-upgrades**; container **digest pinning** with **Renovate**; only auto-update what’s safe. ([Ubuntu Documentation][13], [docs.renovatebot.com][14])
* **CI/CD**: **GitHub Actions** with **Environments** and **Required Reviewers**; optional Tailscale Action to reach private nodes during deploy. ([GitHub Docs][15], [Tailscale][16])

---

## 1) Environments & Order of Operations

We build **additively**—every stage produces components used by the next stage. No host changes until preceding gates pass.

### Environments

* **Local (Laptop)**:

  * VM “staging cluster”: 3× Ubuntu 24.04 VMs (amd64). Multipass (one-liner VMs) or QEMU/KVM if you want to test aarch64 cloud images. ([Ubuntu Documentation][17])
  * Optional **ARM emulation** VM (slow) using `qemu-system-aarch64` with cloud-init NoCloud seed for closer Pi parity. ([Ubuntu Documentation][18], [Cloud-Init][19])
* **Prod (Physical)**: 3× Raspberry Pi 5.

### Stage gates (must pass to proceed)

1. **M0 Local repo & toolchain** → lint/tests pass.
2. **M1 Local VMs up** → time sync OK, SSH redundancy OK.
3. **M2 Base role** → idempotent; `chronyc` OK; unattended-upgrades enabled. ([Ubuntu Documentation][13])
4. **M3 Podman + Quadlet** → local services healthy; auto-update behavior verified. ([docs.podman.io][2])
5. **M4 Observability** → Prometheus targets UP; journald logs flowing to Loki. ([Prometheus][10], [Grafana Labs][12])
6. **M5 Ingress** → Caddy or Traefik routing to services.
7. **M6 Vault + (optional) Keycloak** → Ansible Vault lookups succeed; Grafana OIDC login OK.
8. **M7 GitHub CI/CD** → pipelines green; **Environment approvals** wired; deploy to **local VMs** via Tailscale Action (optional). ([GitHub Docs][20], [Tailscale][16])
9. **M8 Canary Pi** → only one Pi, serial=1, all preflights green.
10. **M9 Full Pi rollout** → staged, reversible.

---

## 2) Local Virtualization (Laptop)

### Option A — Multipass (recommended, cross-platform)

```bash
# Install (Linux example)
sudo snap install multipass

# Create 3 VMs to mimic the Pi cluster (names align with prod inventory)
multipass launch 24.04 --name vm-a --cpus 2 --mem 4G --disk 30G
multipass launch 24.04 --name vm-b --cpus 2 --mem 4G --disk 30G
multipass launch 24.04 --name vm-c --cpus 2 --mem 4G --disk 30G
```

Multipass provides fast Ubuntu VMs on Linux/macOS/Windows; you can pass cloud-init with `--cloud-init` too. ([Ubuntu Documentation][17])

### Option B — ARM64 VM (closer to Pi; slower)

Use Ubuntu ARM64 cloud image with **QEMU/KVM** and **cloud-init NoCloud** (create `cidata` seed ISO). ([Ubuntu Documentation][18], [Cloud-Init][21])

---

## 3) Repository layout

```
repo/
├─ ansible/
│  ├─ inventories/
│  │  ├─ local/hosts.yml   # vm-a/b/c
│  │  └─ prod/hosts.yml    # pi-a/b/c
│  ├─ group_vars/{all,arm64,amd64,observability}.yml
│  ├─ roles/
│  │  ├─ base/        # users, OpenSSH drop-in, Tailscale, chrony, unattended-upgrades
│  │  ├─ podman/      # rootless defaults, quadlet dirs, auto-update timer
│  │  ├─ ingress/     # caddy or traefik
│  │  ├─ monitoring/  # prometheus, grafana, node_exporter
│  │  └─ logging/     # loki, promtail (journald)
│  ├─ playbooks/
│  │  ├─ 00-bootstrap.yml
│  │  ├─ 10-base.yml
│  │  ├─ 20-podman.yml
│  │  ├─ 30-observability.yml
│  │  ├─ 40-ingress.yml
│  │  └─ 50-secrets-sso.yml
│  └─ molecule/default/{molecule.yml,converge.yml,verify.yml}
├─ quadlet/   # *.container/*.volume files (identical between VM and Pi)
├─ scripts/{preflight_time.sh,preflight_ssh.sh,verify_services.sh}
├─ .github/workflows/{ci.yml,deploy-staging.yml,deploy-prod.yml}
├─ renovate.json
├─ CLAUDE.md
└─ PROJECTPLAN.md
```

---

## 4) Hard guardrails

* **Time**: `chrony` uses **NTS** server `time.cloudflare.com` + **NIST** ITS servers; hard gate if offset > 100 ms or stratum > 3. ([Cloudflare Docs][5], [NIST][7])
* **SSH**: Keep **OpenSSH** and **Tailscale SSH** alive at all times; never modify both in one change. Tailscale SSH uses port 22 and doesn’t mutate your OpenSSH config. ([Tailscale][9])
* **APTs**: Security updates auto-applied via **unattended-upgrades**. ([Ubuntu Documentation][13])
* **Containers**: Use **Quadlet** and **pinned digests**; selective **podman-auto-update** (timer at midnight by default, configurable). ([docs.podman.io][2])

---

## 5) Observability (local → prod)

* **Prometheus + node\_exporter**: scrape `:9100` on all nodes. ([Prometheus][10], [GitHub][11])
* **Loki + Promtail**: **journald** scrape on each node; no per-app log hacks. ([Grafana Labs][12])
* **Grafana**: dashboards + health `/api/health`.

---

## 6) Secrets & SSO (phase 2)

* **Vault** for secrets (KV v2) with Ansible lookups (`community.hashi_vault`); wire AppRole or token via GitHub secrets.
* **Keycloak** as OIDC IdP for app SSO (Grafana, etc.).

---

## 7) GitHub CI/CD (source of truth)

### Key concepts

* Use **GitHub Environments**: `staging` (VMs) and `prod` (Pis) with **Required Reviewers**. Jobs block until manual approval. ([GitHub Docs][20])
* **Branch protection** on `main` (PRs, status checks). ([GitHub Docs][22])
* Optional **Tailscale Action** to connect workflows to your tailnet for remote Ansible runs (ephemeral auth key). ([Tailscale][16], [GitHub][23])

### `.github/workflows/ci.yml` (lint + unit tests)

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [ dev ]
jobs:
  lint-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v5
        with: { python-version: '3.11' }
      - name: Install deps
        run: |
          pip install ansible ansible-lint yamllint molecule molecule-podman pytest
          ansible-galaxy collection install containers.podman
      - name: Lint
        run: |
          yamllint .
          ansible-lint
      - name: Molecule (example)
        run: |
          molecule test
```

(Molecule Podman example & containers.podman collection.) ([ansible.readthedocs.io][4], [Ansible][3])

### `.github/workflows/deploy-staging.yml` (local VMs)

```yaml
name: Deploy (staging VMs)
on:
  workflow_dispatch:
  push:
    branches: [ main ]
jobs:
  deploy-staging:
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - name: Connect tailnet (optional)
        uses: tailscale/github-action@v3
        with:
          oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
          oauth-secret:    ${{ secrets.TS_OAUTH_SECRET }}
          tags: tag:ci
      - name: Install Ansible
        run: pip install ansible && ansible-galaxy collection install containers.podman
      - name: Preflight (time/ssh) and check-mode
        run: |
          ansible -i ansible/inventories/local/hosts.yml all -m shell -a 'chronyc tracking'
          ansible-playbook -i ansible/inventories/local/hosts.yml ansible/playbooks/10-base.yml --check --diff
      - name: Apply to staging VMs (serial=1)
        run: ansible-playbook -i ansible/inventories/local/hosts.yml ansible/playbooks/10-base.yml -e "serial=1"
```

(“Environment” gates allow manual approvals before downstream jobs.) ([GitHub Docs][20])
(Tailscale Action makes the runner part of your tailnet temporarily.) ([GitHub][23])

### `.github/workflows/deploy-prod.yml` (Pi canary then rest)

```yaml
name: Deploy (prod Pis)
on:
  workflow_dispatch:
jobs:
  canary:
    runs-on: ubuntu-latest
    environment: prod
    steps:
      - uses: actions/checkout@v4
      - name: Connect tailnet
        uses: tailscale/github-action@v3
        with:
          oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
          oauth-secret:    ${{ secrets.TS_OAUTH_SECRET }}
          tags: tag:ci
      - name: Install Ansible
        run: pip install ansible && ansible-galaxy collection install containers.podman
      - name: Drift/time gates (abort if bad)
        run: |
          ansible -i ansible/inventories/prod/hosts.yml pi-canary -m shell -a 'chronyc tracking'
      - name: Canary apply (serial=1)
        run: |
          ansible-playbook -i ansible/inventories/prod/hosts.yml ansible/playbooks/10-base.yml --limit pi-a -e "serial=1"
  rollout:
    needs: canary
    runs-on: ubuntu-latest
    environment: prod
    steps:
      - uses: actions/checkout@v4
      - name: Connect tailnet
        uses: tailscale/github-action@v3
        with:
          oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
          oauth-secret:    ${{ secrets.TS_OAUTH_SECRET }}
          tags: tag:ci
      - name: Full apply (serial=1)
        run: |
          ansible-playbook -i ansible/inventories/prod/hosts.yml ansible/playbooks/10-base.yml -e "serial=1"
```

(**Required Reviewers** on the `prod` environment will hold these jobs until you approve.) ([GitHub Docs][15])

---

## 8) Roles & Key Config

### `base` role (idempotent)

* Users: `william` + **break-glass** `breakfix` (separate key).
* SSH: manage a **drop-in** (`/etc/ssh/sshd_config.d/10-lab.conf`), **don’t** edit main file; **never** disable OpenSSH.
* **Tailscale** + **Tailscale SSH** (second door; port 22; policy-driven). ([Tailscale][9])
* **chrony**:

  ```conf
  server time.cloudflare.com iburst nts
  server time.nist.gov iburst
  server ntp-a.nist.gov iburst
  server ntp-b.nist.gov iburst
  ntsdumpdir /var/lib/chrony
  makestep 0.1 3
  ```

  (NTS + NIST; chrony supports NTS; Cloudflare docs show usage.) ([Cloudflare Docs][5], [NIST][7])
* **unattended-upgrades** on. ([Ubuntu Documentation][13])

### `podman` role

* Rootless defaults; Quadlet dirs; enable `podman-auto-update.timer` where safe. Midnight timer is the default (configurable). ([docs.podman.io][24])

### `monitoring` & `logging`

* **node\_exporter** on all nodes; **Prometheus** server; **Grafana** UI. ([Prometheus][10])
* **Promtail** scrapes **journald** and ships to **Loki**. ([Grafana Labs][12])

### `ingress`

* **Caddy** (simple) or **Traefik** (labels/middlewares). Pick one and standardize.

### `secrets-sso` (phase 2)

* **Vault** (KV v2) + Ansible `community.hashi_vault` lookups.
* **Keycloak** for Grafana/Gitea OIDC (optional).

---

## 9) Preflight scripts (used locally & in CI)

`scripts/preflight_time.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
chronyc -n tracking
off=$(chronyc tracking | awk '/Last offset/ {print ($3<0?-1*$3:$3)}')
stratum=$(chronyc tracking | awk '/Stratum/ {print $3}')
awk -v o="$off" -v s="$stratum" 'BEGIN {exit !(o<0.1 && s<=3)}'
```

`scripts/preflight_ssh.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
host="$1"
ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" -- 'true' && echo "OpenSSH OK" || exit 1
# Optional TS path probe:
ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" -- 'tailscale status >/dev/null' && echo "Tailscale path OK" || true
```

---

## 10) Rollback strategy

* **Containers**: images referenced by **digest**. Revert the previous digest in Git and re-apply (canary first). **Renovate** manages PRs to bump tags/digests—config `pinDigests` to keep immutability. ([docs.renovatebot.com][14], [docs.mend.io][25])
* **System config**: use Ansible `serial: 1` and keep previous Quadlet unit files; revert commit to known-good state.
* **Network/SSH**: never change both planes at once. If OpenSSH breaks, Tailscale SSH still works (policy-based, port 22). ([Tailscale][9])

---

## 11) Risks & mitigations

* **ARM quirks**: VM staging is amd64 by default; if you suspect arch issues, spin a **QEMU aarch64** VM with a 24.04 arm64 cloud image to validate. ([Ubuntu Documentation][18])
* **Auto-updates**: enable Podman auto-update only for low-risk services and pair it with healthchecks + Observability. ([docs.podman.io][26])
* **Approvals**: require **GitHub Environment** approvals for `prod` to prevent accidental pushes to Pis. ([GitHub Docs][20])

---

## 12) Quick refs

* **Quadlet/Systemd** (design + usage). ([docs.podman.io][2])
* **Podman auto-update** (timer at midnight by default). ([docs.podman.io][24])
* **Unattended updates** (Ubuntu Server guide). ([Ubuntu Documentation][13])
* **chrony NTS** (Cloudflare) + **NIST** servers. ([Cloudflare Docs][5], [NIST][7])
* **Promtail config** (journald). ([Grafana Labs][12])
* **node\_exporter** guide. ([Prometheus][10])
* **Multipass** quick start. ([Ubuntu Documentation][17])
* **GitHub Environments** & approvals; **Tailscale Action**. ([GitHub Docs][20], [Tailscale][16])
