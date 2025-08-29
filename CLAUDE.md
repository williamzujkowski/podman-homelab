# **CLAUDE.md**

> **Purpose:** Operational playbook for the **Claude CLI agent** in this repo. Infrastructure is **deployed to production Raspberry Pis**. Your job is to **propose changes, test locally, open PRs, and follow canary deployment patterns**—not to YOLO into prod.

**Current Status:** ✅ **PRODUCTION DEPLOYED** - Services running on Raspberry Pi cluster (192.168.1.x)

---

## 0) Current Infrastructure State

### Production Raspberry Pi Cluster
| Node | IP | Role | Services |
|------|-----|------|----------|
| **pi-a** | 192.168.1.12 | Monitoring/Canary | Prometheus, Grafana, Loki |
| **pi-b** | 192.168.1.11 | Ingress | Caddy/Traefik |
| **pi-c** | 192.168.1.10 | Worker | Application services |
| **pi-d** | 192.168.1.13 | Storage | MinIO, Backups |

### Access Points
- **Direct**: `http://192.168.1.12:3000` (Grafana), `http://192.168.1.12:9090` (Prometheus)
- **Via Ingress**: `https://grafana.homelab.grenlan.com` (requires /etc/hosts entry)
- **Certificate**: Cloudflare Origin CA (15-year validity)

---

## 1) Golden rules

1. **Local → Staging VM → Prod**. Test locally first, then canary to pi-a, then roll out. ([GitHub Docs][20])
2. **Two SSH doors open** at all times: OpenSSH **and** Tailscale SSH. **Never** change both in the same PR. Tailscale SSH uses port 22 and doesn't modify OpenSSH config. ([Tailscale][9])
3. **Time is a hard gate**: deployments must verify `chronyc tracking` on targets; drift ≤100 ms, stratum ≤3. chrony should use `time.cloudflare.com nts` + NIST servers. ([Cloudflare Docs][5], [NIST][7])
4. **Immutable containers**: deploy via **Quadlet** with **digest-pinned** images. Use **Renovate** to propose tag/digest bumps—do not pull `:latest`. ([docs.podman.io][2], [docs.renovatebot.com][14])
5. **Everything via Ansible** with `containers.podman` modules. No ad-hoc host edits. ([Ansible][3])
6. **Internal only**: Services must NOT be accessible from public internet. Use Cloudflare Origin CA but keep DNS records unproxied.

---

## 2) Allowed operations

* Edit Ansible roles/playbooks, inventories, Quadlet files, GitHub Workflows.
* Run **lint/tests** locally (yamllint, ansible-lint, Molecule). ([ansible.readthedocs.io][4])
* Open **PRs** with clear change logs, test notes, and rollback instructions.
* Use **GitHub Environments** to route deployments; do not bypass required reviewers. ([GitHub Docs][27])
* Deploy **Cloudflare Origin certificates** for internal HTTPS.
* Configure **local-only network access** rules in Caddy/Traefik.

## 3) Forbidden operations

* Direct, manual SSH changes on prod Pis.
* Restarting both SSH planes in one PR.
* Modifying time sources to leap-smeared + standard mix.
* Using floating image tags in prod.
* Exposing services to public internet (keep DNS records unproxied).
* Bypassing canary deployment pattern (pi-a first, then others).

---

## 4) Local toolchain expectations

* **Podman** installed locally; use **Quadlet** for systemd-managed test units. ([docs.podman.io][2])
* **Multipass** for quick Ubuntu VMs (preferred) or **QEMU/KVM** + cloud-init NoCloud (for ARM emulation). ([Ubuntu Documentation][17], [Cloud-Init][19])
* **Ansible + containers.podman** collection; **Molecule** for role tests. ([Ansible][3], [ansible.readthedocs.io][4])

---

## 5) Required preflight before any remote apply

```bash
# 1) Time gate (abort if drift > 0.1s or stratum > 3)
scripts/preflight_time.sh

# 2) SSH redundancy (prove OpenSSH; Tailscale optional probe)
scripts/preflight_ssh.sh <target_host>
```

If time is off: ensure `chrony.conf` includes:

```
server time.cloudflare.com iburst nts
server time.nist.gov iburst
```

(Cloudflare NTS + NIST official servers.) ([Cloudflare Docs][5], [NIST][7])

---

## 6) Change workflow (you must follow this)

1. **Plan & lint**

   * `yamllint . && ansible-lint`
   * `systemd-analyze verify quadlet/*.container`
   * `molecule test` for touched roles (Podman). ([ansible.readthedocs.io][4])

2. **Local simulate**

   * Run updated Quadlet/containers locally; confirm health endpoints.

3. **Open PR**

   * Include: what changed, why, healthchecks, and exact **rollback digest**.

4. **CI runs** (`.github/workflows/ci.yml`)

   * Lint + Molecule must pass.

5. **Deploy to VMs (staging)**

   * Trigger `deploy-staging.yml`. If using private addressing, the workflow may connect to tailnet using **Tailscale GitHub Action**. Wait for staging **environment** (if approvals are enabled). ([Tailscale][16])

6. **Canary Pi**

   * Trigger `deploy-prod.yml`. GitHub **`prod` environment** forces manual approval. Apply to `pi-a` only with `serial: 1`. ([GitHub Docs][20])

7. **Full rollout**

   * Proceed only if canary passes healthchecks (Prometheus target up, Grafana `/api/health`, Loki `/ready`).

If anything fails → **revert digest** and re-apply to canary.

---

## 7) Typical tasks (prompt templates)

**A. Update a service image safely**

> Find the newest **compatible** tag for `<service>`, update the Quadlet to **pin the image digest**, run local tests, open a PR with verification steps and rollback digest. Ensure `podman-auto-update` is **off** for this critical service unless explicitly allowed.

(Use Renovate for automated PRs; enable `pinDigests`.) ([docs.renovatebot.com][14])

**B. Add a new host to staging**

> Create `vm-d` in Multipass, add it to `ansible/inventories/local/hosts.yml`, run `00-bootstrap.yml` in `--check`, then apply. Verify time/SSH preflights and exporters.

**C. Wire a new log source**

> Ensure container logs to **journald**; promtail picks it up; verify log flow in Grafana Explore. ([Grafana Labs][12])

---

## 8) GitHub specifics you will use

* **Environments & Required Reviewers**: add `environment: staging` / `environment: prod` to jobs; human must **Approve and deploy** to continue. ([GitHub Docs][20])
* **Tailscale Action** in workflows to reach private nodes during deploys. ([GitHub][23])
* **Branch protection** on `main`: require PRs + CI status checks. ([GitHub Docs][22])

---

## 9) Reference links (for you)

* **Quadlet & systemd**; **podman-auto-update** (timer defaults). ([docs.podman.io][2])
* **containers.podman** collection; **Molecule Podman** example. ([Ansible][3], [ansible.readthedocs.io][4])
* **chrony NTS** (Cloudflare) + **NIST ITS** list. ([Cloudflare Docs][5], [NIST][7])
* **Promtail (journald)**; **node\_exporter** guide. ([Grafana Labs][12], [Prometheus][10])
* **Multipass** docs (VMs on Linux/macOS/Windows). ([Ubuntu Documentation][17])
* **GitHub Environments & approvals**; **Tailscale Action**. ([GitHub Docs][20], [Tailscale][16])
* **Renovate** Docker digest pinning guidance. ([docs.renovatebot.com][14])

---

## 10) TLS Certificate Management

### Let's Encrypt via Certbot
Certificates are managed independently from Traefik using certbot with Cloudflare DNS-01 challenge.

* **Location**: `/etc/letsencrypt/live/homelab.grenlan.com/` on pi-b (192.168.1.11)
* **Traefik integration**: Certificates copied to `/etc/traefik/certs/` for container access
* **Auto-renewal**: Systemd timer (`certbot-renew.timer`) runs twice daily
* **Renewal hook**: Automatically restarts Traefik on successful renewal
* **Expiry**: 90 days (renews ~30 days before expiry)

### Certificate Commands
```bash
# Manual renewal test (dry run)
ssh pi@192.168.1.11 "sudo /opt/certbot-env/bin/certbot renew --dry-run"

# Check certificate status
ssh pi@192.168.1.11 "sudo /opt/certbot-env/bin/certbot certificates"

# View renewal timer status
ssh pi@192.168.1.11 "sudo systemctl status certbot-renew.timer"

# Force certificate copy to Traefik (if needed)
ssh pi@192.168.1.11 "sudo cp /etc/letsencrypt/live/homelab.grenlan.com/*.pem /etc/traefik/certs/ && podman restart systemd-traefik"
```

## 11) Emergency rollbacks

* **Containers**: revert to previous **digest**; re-apply to canary (`serial: 1`), then full.
* **Ingress**: keep prior unit file; `systemctl revert`/switch symlink.
* **SSH**: if OpenSSH path gets borked, use **Tailscale SSH** (policy-based, port 22) to revert the drop-in. ([Tailscale][9])
* **Certificates**: Previous certs remain in `/etc/letsencrypt/archive/`. To rollback: `sudo cp /etc/letsencrypt/archive/homelab.grenlan.com/*1.pem /etc/traefik/certs/`

---

## 12) Production Access Information

### Direct Access URLs (Internal Network Only)
- **Grafana**: http://192.168.1.12:3000 (admin/admin)
- **Prometheus**: http://192.168.1.12:9090
- **Loki**: http://192.168.1.12:3100

### HTTPS Access (with Let's Encrypt)
Certificates are managed via certbot with Cloudflare DNS-01 challenge.

Add to `/etc/hosts`:
```
192.168.1.11  homelab.grenlan.com grafana.homelab.grenlan.com prometheus.homelab.grenlan.com loki.homelab.grenlan.com
```

Then access:
- https://grafana.homelab.grenlan.com (browser-trusted ✅)
- https://prometheus.homelab.grenlan.com (browser-trusted ✅)
- https://loki.homelab.grenlan.com (browser-trusted ✅)

### Quick Commands
```bash
# Check all services
curl -s http://192.168.1.12:9090/-/healthy  # Prometheus
curl -s http://192.168.1.12:3000/api/health  # Grafana
curl -s http://192.168.1.12:3100/ready       # Loki

# SSH to nodes
ssh pi@192.168.1.12  # pi-a (monitoring)
ssh pi@192.168.1.11  # pi-b (ingress)
ssh pi@192.168.1.10  # pi-c (worker)
ssh pi@192.168.1.13  # pi-d (storage)
```

---


[1]: https://documentation.ubuntu.com/multipass/?utm_source=chatgpt.com "Multipass documentation"
[2]: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html?utm_source=chatgpt.com "podman-systemd.unit"
[3]: https://docs.ansible.com/ansible/latest/collections/containers/podman/index.html?utm_source=chatgpt.com "Containers.Podman — Ansible Community Documentation"
[4]: https://ansible.readthedocs.io/projects/molecule/examples/podman/?utm_source=chatgpt.com "Using podman containers - Ansible Molecule"
[5]: https://developers.cloudflare.com/time-services/nts/?utm_source=chatgpt.com "Network Time Security"
[6]: https://www.cloudflare.com/time/?utm_source=chatgpt.com "Cloudflare Time Services"
[7]: https://tf.nist.gov/tf-cgi/servers.cgi?utm_source=chatgpt.com "NIST Internet Time Servers"
[8]: https://www.nist.gov/pml/time-and-frequency-division/time-distribution/internet-time-service-its?utm_source=chatgpt.com "NIST Internet Time Service (ITS)"
[9]: https://tailscale.com/kb/1193/tailscale-ssh?utm_source=chatgpt.com "configured to use Tailscale SSH"
[10]: https://prometheus.io/docs/guides/node-exporter/?utm_source=chatgpt.com "Monitoring Linux host metrics with the Node Exporter"
[11]: https://github.com/prometheus/node_exporter?utm_source=chatgpt.com "prometheus/node_exporter: Exporter for machine metrics"
[12]: https://grafana.com/docs/loki/latest/send-data/promtail/configuration/?utm_source=chatgpt.com "Configure Promtail | Grafana Loki documentation"
[13]: https://documentation.ubuntu.com/server/how-to/software/automatic-updates/?utm_source=chatgpt.com "Automatic updates - Ubuntu Server"
[14]: https://docs.renovatebot.com/docker/?utm_source=chatgpt.com "Docker - Renovate Docs"
[15]: https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment?utm_source=chatgpt.com "Managing environments for deployment"
[16]: https://tailscale.com/kb/1276/tailscale-github-action?utm_source=chatgpt.com "Tailscale GitHub Action"
[17]: https://documentation.ubuntu.com/server/how-to/virtualisation/multipass/?utm_source=chatgpt.com "How to create a VM with Multipass"
[18]: https://documentation.ubuntu.com/server/how-to/virtualisation/qemu/?utm_source=chatgpt.com "QEMU - Ubuntu Server"
[19]: https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html?utm_source=chatgpt.com "NoCloud - cloud-init 25.2 documentation - Read the Docs"
[20]: https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-what-your-workflow-does/using-environments-for-deployment?utm_source=chatgpt.com "Using environments for deployment"
[21]: https://cloudinit.readthedocs.io/en/21.1/topics/datasources/nocloud.html?utm_source=chatgpt.com "NoCloud — cloud-init 21.1 documentation"
[22]: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/managing-a-branch-protection-rule?utm_source=chatgpt.com "Managing a branch protection rule"
[23]: https://github.com/tailscale/github-action?utm_source=chatgpt.com "A GitHub Action to connect your workflow to your Tailscale ..."
[24]: https://docs.podman.io/en/v4.2/markdown/podman-auto-update.1.html?utm_source=chatgpt.com "podman-auto-update"
[25]: https://docs.mend.io/wsk/renovate-package-rules-guide?utm_source=chatgpt.com "Renovate Package Rules Guide"
[26]: https://docs.podman.io/en/latest/markdown/podman-auto-update.1.html?utm_source=chatgpt.com "podman-auto-update"
[27]: https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments?utm_source=chatgpt.com "Deployments and environments"
