#!/bin/bash
# Full deployment script for Raspberry Pi cluster
# Run playbooks in correct order with dependencies

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE} Raspberry Pi Cluster Deployment ${NC}"
echo -e "${BLUE}================================${NC}"

# Function to run playbook with status
run_playbook() {
    local playbook=$1
    local description=$2
    
    echo -e "\n${YELLOW}Running: ${description}${NC}"
    echo "Playbook: ${playbook}"
    
    if ansible-playbook "${playbook}" --diff; then
        echo -e "${GREEN}✓ ${description} completed${NC}"
    else
        echo -e "${RED}✗ ${description} failed${NC}"
        exit 1
    fi
}

# Check connectivity
echo -e "${YELLOW}Testing connectivity...${NC}"
ansible -i inventories/prod/hosts.yml pis -m ping

# Run playbooks in order
run_playbook "playbooks/10-base.yml" "Base system configuration"
run_playbook "playbooks/20-podman.yml" "Podman container runtime"
run_playbook "playbooks/30-observability.yml" "Monitoring stack (Prometheus, Grafana, Loki)"
run_playbook "playbooks/40-ingress.yml" "Ingress controller (Traefik/Caddy)"

# Additional configurations
echo -e "\n${YELLOW}Running additional configurations...${NC}"

# Start services that aren't running
echo "Starting native services..."
ansible -i inventories/prod/hosts.yml pi-a -m systemd -a "name=prometheus state=started enabled=yes" --become || true
ansible -i inventories/prod/hosts.yml pi-a -m systemd -a "name=grafana state=started enabled=yes" --become || true
ansible -i inventories/prod/hosts.yml pi-b -m systemd -a "name=nginx state=started enabled=yes" --become || true
ansible -i inventories/prod/hosts.yml pi-d -m systemd -a "name=minio state=started enabled=yes" --become || true

echo -e "\n${GREEN}================================${NC}"
echo -e "${GREEN} Deployment Complete!${NC}"
echo -e "${GREEN}================================${NC}"

echo -e "\n${BLUE}Service URLs:${NC}"
echo "Prometheus: http://pi-a.grenlan.com:9090 (192.168.1.12:9090)"
echo "Grafana: http://pi-a.grenlan.com:3000 (192.168.1.12:3000)"
echo "Traefik: http://pi-b.grenlan.com:8080 (192.168.1.11:8080)"
echo "MinIO: http://pi-d.grenlan.com:9000 (192.168.1.13:9000)"

echo -e "\n${BLUE}SSH Access:${NC}"
echo "pi-a: ssh pi@pi-a.grenlan.com (192.168.1.12)"
echo "pi-b: ssh pi@pi-b.grenlan.com (192.168.1.11)"
echo "pi-c: ssh pi@pi-c.grenlan.com (192.168.1.10)"
echo "pi-d: ssh pi@pi-d.grenlan.com (192.168.1.13)"