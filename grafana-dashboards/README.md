# Grafana Dashboards for Raspberry Pi Homelab

This directory contains comprehensive Grafana dashboards designed specifically for monitoring the Raspberry Pi homelab infrastructure.

## Dashboard Overview

### 1. Cluster Overview Dashboard (`cluster-overview.json`)
**UID:** `homelab-cluster-overview`
**Folder:** Homelab

A high-level view of the entire cluster providing:
- **Cluster Health**: Node count, average CPU/memory/disk usage
- **Node Status**: Individual node health indicators  
- **Network & Storage**: Aggregate network traffic and disk I/O across all nodes
- **System Health**: Load averages and uptime across the cluster

**Key Metrics:**
- `up{job="node_exporter"}` - Node availability
- `rate(node_cpu_seconds_total{mode="idle"}[5m])` - CPU usage
- `node_memory_MemAvailable_bytes` - Memory usage
- `node_filesystem_avail_bytes` - Disk usage
- `rate(node_network_*_bytes_total[5m])` - Network traffic

### 2. Node Details Dashboard (`node-details.json`)
**UID:** `homelab-node-details`
**Folder:** Homelab

Detailed metrics for individual nodes with node selection variable:
- **Node Information**: Status, uptime, hardware specs, temperature
- **CPU Details**: Usage by mode and per-core breakdown
- **Memory Details**: Usage breakdown, swap monitoring
- **Storage Details**: Filesystem usage and disk I/O operations
- **Network Details**: Interface traffic and error monitoring

**Features:**
- Node selector variable (`$node`) for filtering
- Temperature monitoring (if hardware sensors available)
- Detailed resource utilization breakdowns
- Network error and drop detection

### 3. Service Health Dashboard (`service-health.json`)
**UID:** `homelab-service-health`
**Folder:** Homelab

Comprehensive service monitoring:
- **Service Overview**: Total services, availability percentage
- **Service Status Table**: Current status of all monitored services
- **Monitoring Services**: Prometheus, Grafana, Loki, Traefik, Node Exporters
- **Service Performance**: Uptime history and internal metrics
- **Container Health**: Resource usage for containerized services

**Monitored Services:**
- Prometheus (`job="prometheus"`)
- Grafana (`job="grafana"`)
- Loki (`job="loki"`)
- Traefik (`job="traefik"`)
- Node Exporters (`job="node_exporter"`)
- Container Runtime (if available)

### 4. Authentik Monitoring Dashboard (`authentik-monitoring.json`)
**UID:** `homelab-authentik-monitoring`
**Folder:** Security

Authentication service monitoring:
- **Service Status**: Authentik server, worker, PostgreSQL, Redis health
- **Authentication Metrics**: Login attempts, failed authentications
- **Container Performance**: CPU, memory, network usage
- **Application Logs**: Recent logs from Authentik and database
- **Security Metrics**: Authentication events breakdown
- **Response Times**: HTTP performance metrics (via Traefik)

**Data Sources:**
- Prometheus metrics for container stats
- Loki logs for authentication events
- Traefik metrics for response times

### 5. Alert Dashboard (`alert-dashboard.json`)
**UID:** `homelab-alert-dashboard`
**Folder:** Alerts

Critical monitoring thresholds and alerts:
- **Critical Alert Status**: Services down, high resource usage
- **Detailed Alert Information**: Tables of problematic services/nodes
- **Resource Usage Alerts**: CPU >80%, Memory >85%, Disk >90%
- **Temperature & Health**: Thermal alerts, system load warnings
- **Network & Security**: Interface errors, failed authentication attempts
- **Alert Recommendations**: Suggested Prometheus alert rules

**Alert Thresholds:**
- CPU Usage: >80% critical, >60% warning
- Memory Usage: >85% critical, >60% warning  
- Disk Usage: >90% critical, >70% warning
- Temperature: >80°C critical, >70°C warning
- System Load: >4 (for 4-core Pi) warning

## Installation and Usage

### Method 1: Ansible Playbook (Recommended)

Run the comprehensive import playbook:

```bash
cd /home/william/git/podman-homelab/ansible
ansible-playbook -i inventories/prod/hosts.yml \
    playbooks/60-grafana-dashboards.yml \
    --limit monitoring_nodes
```

### Method 2: Import Script

Use the provided script for flexible import options:

```bash
# Import via Ansible (default)
./scripts/import-grafana-dashboards.sh

# Import directly via API
./scripts/import-grafana-dashboards.sh --method api

# List available dashboards
./scripts/import-grafana-dashboards.sh --list

# Custom Grafana instance
./scripts/import-grafana-dashboards.sh \
    --grafana-url http://192.168.1.12:3000 \
    --grafana-user admin \
    --grafana-password your-password
```

### Method 3: Manual Import

1. Access Grafana web interface at `http://192.168.1.12:3000`
2. Login with admin credentials
3. Navigate to **+ > Import**  
4. Upload each JSON file or paste the JSON content
5. Configure folder placement as needed

## Dashboard Configuration

### Data Sources Required

All dashboards expect these data sources to be configured:

- **Prometheus** (UID: `prometheus`)
  - URL: `http://localhost:9090`
  - Default data source
  
- **Loki** (UID: `loki`)  
  - URL: `http://localhost:3100`
  - For log-based panels

### Variables and Templating

**Node Details Dashboard** includes:
- `$node` - Node selector variable for filtering metrics to specific instances

### Folder Structure

Dashboards are organized into logical folders:
- **Homelab** - Core infrastructure monitoring
- **Security** - Authentication and security-related dashboards  
- **Alerts** - Alert management and threshold monitoring

## Customization

### Modifying Thresholds

Alert thresholds can be adjusted in the dashboard JSON:

```json
"thresholds": {
  "mode": "absolute",
  "steps": [
    {"color": "green", "value": null},
    {"color": "yellow", "value": 70},
    {"color": "red", "value": 90}
  ]
}
```

### Adding New Panels

To add custom panels:
1. Edit the dashboard in Grafana UI
2. Export the updated JSON
3. Replace the file in this directory
4. Re-run the import process

### Prometheus Queries

Common query patterns used in dashboards:

```promql
# CPU usage percentage
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage percentage  
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100

# Disk usage percentage
100 - ((node_filesystem_avail_bytes * 100) / node_filesystem_size_bytes)

# Network traffic rate
rate(node_network_receive_bytes_total[5m])

# Service availability
up{job="service_name"}
```

## Troubleshooting

### Dashboard Import Issues

1. **API Connection Failed**
   ```bash
   curl -u admin:admin http://192.168.1.12:3000/api/health
   ```

2. **Missing Data Sources**
   - Verify Prometheus is accessible at `:9090`
   - Check Loki is running on `:3100`
   - Confirm data source UIDs match dashboard expectations

3. **No Data in Panels**
   - Check Prometheus targets are up: `http://192.168.1.12:9090/targets`
   - Verify node_exporter is running on all nodes
   - Check firewall rules for port 9100

4. **Permission Issues**
   ```bash
   sudo chown grafana:grafana /var/lib/grafana/dashboards/*.json
   sudo systemctl restart grafana-server
   ```

### Performance Optimization

For large clusters or high-resolution metrics:
1. Adjust refresh rates in dashboard settings
2. Reduce query time ranges for resource-intensive panels
3. Use recording rules for frequently-used calculations
4. Consider metric retention policies in Prometheus

## Maintenance

### Regular Updates

1. **Dashboard Versioning**: Track changes in git
2. **Backup**: Export dashboards before major changes
3. **Testing**: Verify dashboards after Grafana upgrades
4. **Documentation**: Update this README when adding new dashboards

### Monitoring the Monitors

The dashboards themselves should be monitored:
- Grafana service health (included in Service Health dashboard)
- Dashboard load times and responsiveness
- Data source connectivity and query performance

## Contributing

When adding new dashboards:
1. Follow the existing naming convention
2. Include proper metadata (UID, title, tags, folder)
3. Add comprehensive descriptions for panels
4. Update this README with dashboard details
5. Test import process via both methods
6. Include appropriate alert thresholds