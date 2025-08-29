# Grafana Configuration and Dashboard Setup

## Overview

Successfully configured Prometheus as a data source in Grafana and imported essential monitoring dashboards for the Pi homelab infrastructure.

## Configuration Details

### Data Source Configuration
- **Name**: Prometheus
- **Type**: prometheus
- **URL**: http://localhost:9090 (local to Grafana container)
- **Access**: proxy
- **Default**: Yes

### Credentials Used
- **Grafana URL**: http://192.168.1.12:3000
- **Username**: admin
- **Password**: JKmUmdS2cpmJeBY

## Imported Dashboards

### 1. Node Exporter Full (ID: 1860)
- **Dashboard URL**: http://192.168.1.12:3000/d/rYdddlPWk/node-exporter-full
- **Purpose**: Comprehensive system monitoring for all Pi nodes
- **Covers**: CPU, Memory, Disk, Network, System Load
- **Status**: ✅ Successfully imported and working

### 2. Prometheus Stats (ID: 2)
- **Dashboard URL**: http://192.168.1.12:3000/d/27a5bd05-63f8-407a-96d2-7afa859c1222/prometheus-stats
- **Purpose**: Prometheus server performance and statistics
- **Covers**: Scraping metrics, query performance, storage
- **Status**: ✅ Successfully imported and working

### 3. Cadvisor Exporter (ID: 14282)
- **Dashboard URL**: http://192.168.1.12:3000/d/pMEd7m0Mz/cadvisor-exporter
- **Purpose**: Container monitoring and resource usage
- **Covers**: Container CPU, memory, network, disk I/O
- **Status**: ✅ Successfully imported and working

## Monitoring Coverage

### Node Coverage
All 4 Pi nodes are successfully monitored with dual configurations:

1. **pi-a (monitoring role)**
   - Status: ✅ UP
   - CPU Usage: ~1-2%
   - RAM Usage: ~5%
   - Services: Prometheus, Grafana, Node Exporter

2. **pi-b (ingress role)**
   - Status: ✅ UP  
   - CPU Usage: ~0.7%
   - RAM Usage: ~3.3%
   - Services: Node Exporter (Traefik pending)

3. **pi-c (worker role)**
   - Status: ✅ UP
   - CPU Usage: ~0.6%
   - RAM Usage: ~3.4%
   - Services: Node Exporter

4. **pi-d (storage role)**
   - Status: ✅ UP
   - CPU Usage: ~0.6%
   - RAM Usage: ~8.8%
   - Services: Node Exporter (MinIO pending)

### Target Discovery
- **Total Targets**: 16 discovered by Prometheus
- **Active Targets**: 11 UP, 5 DOWN (expected - services not yet deployed)
- **Node Exporters**: 8 instances (4 nodes × 2 configurations each)

## Verified Metrics

✅ **System Metrics**
- CPU usage per node and per core
- Memory usage (total, available, buffers, cache)
- Disk I/O operations and throughput
- Network interface statistics
- System load averages and uptime

✅ **Prometheus Metrics**
- Scraping duration and success rates
- Query performance
- Storage usage
- Rule evaluation

## Scripts Created

### `/home/william/git/podman-homelab/scripts/configure-grafana.sh`
- Comprehensive configuration script
- Creates Prometheus data source
- Imports multiple dashboards
- Tests connectivity and queries

### `/home/william/git/podman-homelab/scripts/import-single-dashboard.sh`
- Imports individual dashboards by ID
- Handles large dashboard JSON files
- Provides detailed import status

### `/home/william/git/podman-homelab/scripts/verify-grafana-setup.sh`  
- Comprehensive verification of setup
- Tests all major functionality
- Displays current metrics and status

### `/home/william/git/podman-homelab/scripts/grafana-summary.sh`
- Quick status overview
- Health checks
- Access information

## Current Status

### Working Services ✅
- Grafana (v12.1.1)
- Prometheus data collection
- Node exporter metrics from all 4 Pis
- Dashboard visualization
- Real-time metric queries

### Pending Services ⏳
- MinIO on pi-d (storage service)
- Traefik on pi-b (reverse proxy)
- Podman exporters on pi-b, pi-c, pi-d

## Next Steps

1. **Explore Dashboards**: Visit the imported dashboards and familiarize with available metrics
2. **Set Up Alerting**: Configure Prometheus alert rules and Grafana notifications  
3. **Deploy Missing Services**: Complete MinIO and Traefik deployments
4. **Custom Dashboards**: Create application-specific monitoring dashboards
5. **Performance Tuning**: Optimize scraping intervals and retention policies

## Troubleshooting

### Dashboard Import Issues
- Some dashboards require specific input variables (DS_PROMETHEUS automatically mapped)
- Large dashboard JSONs may need file-based import approach
- Check Grafana logs for detailed error messages

### Data Source Connectivity
- Ensure Prometheus is accessible on http://localhost:9090 from Grafana container
- Verify network connectivity between containers
- Check Prometheus targets page for scraping issues

### Metric Queries
- Use Grafana's built-in query builder for Prometheus
- Test queries in Prometheus web UI first
- Check metric name spelling and label selectors

## Security Notes

- Default credentials are in use (should be changed in production)
- No HTTPS/TLS configured (acceptable for internal homelab)
- Consider restricting access to Grafana dashboard for production use