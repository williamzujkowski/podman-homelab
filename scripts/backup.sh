#!/bin/bash

set -euo pipefail

# Backup script for homelab infrastructure
# Creates timestamped backups of critical configurations and data

BACKUP_DIR="/home/william/homelab-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Create backup directory
mkdir -p "${BACKUP_PATH}"

echo "==========================================="
echo "   Homelab Infrastructure Backup"
echo "   Timestamp: ${TIMESTAMP}"
echo "==========================================="
echo ""

# Function to backup VM configuration
backup_vm() {
    local vm="$1"
    local vm_backup="${BACKUP_PATH}/${vm}"
    
    echo -e "${YELLOW}Backing up ${vm}...${NC}"
    mkdir -p "${vm_backup}"
    
    # Backup configuration files
    echo "  - Backing up configurations..."
    ssh "${vm}" 'sudo tar czf /tmp/etc-backup.tar.gz \
        /etc/prometheus/ \
        /etc/grafana/ \
        /etc/loki/ \
        /etc/promtail/ \
        /etc/caddy/ \
        /etc/containers/systemd/ \
        2>/dev/null || true' 2>/dev/null
    
    scp "${vm}:/tmp/etc-backup.tar.gz" "${vm_backup}/etc-backup.tar.gz" 2>/dev/null
    ssh "${vm}" 'rm /tmp/etc-backup.tar.gz' 2>/dev/null
    
    # Backup Grafana dashboards and datasources
    if [[ "${vm}" == "vm-a" ]]; then
        echo "  - Backing up Grafana dashboards..."
        curl -s -u admin:admin http://localhost:3000/api/search?type=dash-db | \
            jq -r '.[].uid' | while read uid; do
            if [[ -n "${uid}" ]]; then
                curl -s -u admin:admin "http://localhost:3000/api/dashboards/uid/${uid}" > \
                    "${vm_backup}/dashboard-${uid}.json" 2>/dev/null || true
            fi
        done
        
        echo "  - Backing up Grafana datasources..."
        curl -s -u admin:admin http://localhost:3000/api/datasources > \
            "${vm_backup}/datasources.json" 2>/dev/null || true
    fi
    
    # List running containers
    echo "  - Saving container state..."
    ssh "${vm}" 'sudo podman ps --format json' > "${vm_backup}/containers.json" 2>/dev/null
    
    echo -e "  ${GREEN}✓ ${vm} backup complete${NC}"
}

# Function to backup Prometheus data
backup_prometheus_data() {
    echo -e "${YELLOW}Backing up Prometheus data...${NC}"
    
    # Create a snapshot in Prometheus
    echo "  - Creating Prometheus snapshot..."
    curl -s -X POST http://localhost:9090/api/v1/admin/tsdb/snapshot > /tmp/snapshot.json
    SNAPSHOT_NAME=$(jq -r '.data.name' /tmp/snapshot.json 2>/dev/null || echo "")
    
    if [[ -n "${SNAPSHOT_NAME}" ]]; then
        # Copy snapshot from container
        ssh vm-a "sudo podman exec prometheus tar czf /tmp/prometheus-snapshot.tar.gz /prometheus/snapshots/${SNAPSHOT_NAME}" 2>/dev/null || true
        ssh vm-a "sudo podman cp prometheus:/tmp/prometheus-snapshot.tar.gz /tmp/" 2>/dev/null || true
        scp vm-a:/tmp/prometheus-snapshot.tar.gz "${BACKUP_PATH}/prometheus-snapshot.tar.gz" 2>/dev/null || true
        ssh vm-a 'rm /tmp/prometheus-snapshot.tar.gz' 2>/dev/null || true
        
        # Clean up snapshot
        curl -s -X POST "http://localhost:9090/api/v1/admin/tsdb/delete_series?match[]={__name__=~\".*\"}" > /dev/null 2>&1 || true
        
        echo -e "  ${GREEN}✓ Prometheus data backed up${NC}"
    else
        echo -e "  ${YELLOW}⚠ Could not create Prometheus snapshot${NC}"
    fi
}

# Function to backup Loki data
backup_loki_data() {
    echo -e "${YELLOW}Backing up Loki data...${NC}"
    
    # Backup Loki chunks and index
    ssh vm-a "sudo tar czf /tmp/loki-data.tar.gz /var/lib/containers/storage/volumes/loki-data/_data 2>/dev/null || true" 2>/dev/null || true
    scp vm-a:/tmp/loki-data.tar.gz "${BACKUP_PATH}/loki-data.tar.gz" 2>/dev/null || true
    ssh vm-a 'rm /tmp/loki-data.tar.gz' 2>/dev/null || true
    
    echo -e "  ${GREEN}✓ Loki data backed up${NC}"
}

# Backup ansible configuration
backup_ansible() {
    echo -e "${YELLOW}Backing up Ansible configuration...${NC}"
    
    tar czf "${BACKUP_PATH}/ansible-config.tar.gz" \
        -C /home/william/git/podman-homelab \
        ansible/ \
        quadlet/ \
        scripts/ \
        *.md \
        2>/dev/null || true
    
    echo -e "  ${GREEN}✓ Ansible configuration backed up${NC}"
}

# Main backup process
echo "Starting backup process..."
echo ""

# Backup each VM
for vm in vm-a vm-b vm-c; do
    backup_vm "${vm}"
done
echo ""

# Backup data
backup_prometheus_data
backup_loki_data
echo ""

# Backup Ansible configuration
backup_ansible
echo ""

# Create backup manifest
cat > "${BACKUP_PATH}/manifest.json" << EOF
{
  "timestamp": "${TIMESTAMP}",
  "date": "$(date -Iseconds)",
  "vms": ["vm-a", "vm-b", "vm-c"],
  "components": [
    "prometheus",
    "grafana",
    "loki",
    "caddy",
    "node-exporter",
    "promtail"
  ],
  "backup_size": "$(du -sh ${BACKUP_PATH} | cut -f1)"
}
EOF

# Compress entire backup
echo -e "${YELLOW}Compressing backup...${NC}"
cd "${BACKUP_DIR}"
tar czf "backup-${TIMESTAMP}.tar.gz" "${TIMESTAMP}/"
rm -rf "${TIMESTAMP}/"

BACKUP_SIZE=$(du -h "backup-${TIMESTAMP}.tar.gz" | cut -f1)

echo ""
echo "==========================================="
echo -e "${GREEN}✓ Backup completed successfully!${NC}"
echo "  Location: ${BACKUP_DIR}/backup-${TIMESTAMP}.tar.gz"
echo "  Size: ${BACKUP_SIZE}"
echo ""

# Cleanup old backups (keep last 7 days)
echo "Cleaning up old backups..."
find "${BACKUP_DIR}" -name "backup-*.tar.gz" -mtime +7 -delete 2>/dev/null || true

# List current backups
echo "Current backups:"
ls -lh "${BACKUP_DIR}"/backup-*.tar.gz 2>/dev/null || echo "No backups found"