#!/bin/bash
# Quick deployment script using pre-built images
# This runs AFTER you've flashed and booted all Pis with custom images

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Raspberry Pi Cluster Quick Deploy${NC}"
echo -e "${GREEN}========================================${NC}"

# Configuration
PI_IPS=("10.0.1.10" "10.0.1.11" "10.0.1.12" "10.0.1.13")
PI_NAMES=("pi-a" "pi-b" "pi-c" "pi-d")
DEFAULT_PASSWORD="TempPiPass2024!Change"
SSH_KEY="$HOME/.ssh/pi_ed25519"

# Step 1: Wait for Pis to be ready
echo -e "\n${YELLOW}Step 1: Waiting for Pis to boot and complete cloud-init...${NC}"
echo "This typically takes 5-10 minutes after power-on."
echo "Checking connectivity..."

for i in ${!PI_IPS[@]}; do
    ip="${PI_IPS[$i]}"
    name="${PI_NAMES[$i]}"
    
    echo -n "  Waiting for $name ($ip)..."
    
    # Wait up to 10 minutes for SSH to be available
    timeout=600
    elapsed=0
    while ! nc -zw2 "$ip" 22 2>/dev/null; do
        if [ $elapsed -ge $timeout ]; then
            echo -e " ${RED}✗ Timeout${NC}"
            echo "    $name is not responding. Please check:"
            echo "    - SD card is properly inserted"
            echo "    - Ethernet cable is connected"
            echo "    - Power supply is adequate"
            exit 1
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
    done
    echo -e " ${GREEN}✓ Online${NC}"
done

# Step 2: Generate SSH keys if needed
echo -e "\n${YELLOW}Step 2: Setting up SSH keys...${NC}"
if [ ! -f "$SSH_KEY" ]; then
    echo "  Generating new SSH key..."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "pi-cluster-key"
    echo -e "  ${GREEN}✓ SSH key generated${NC}"
else
    echo -e "  ${GREEN}✓ Using existing SSH key${NC}"
fi

# Step 3: Deploy SSH keys to all Pis
echo -e "\n${YELLOW}Step 3: Deploying SSH keys to all Pis...${NC}"
for i in ${!PI_IPS[@]}; do
    ip="${PI_IPS[$i]}"
    name="${PI_NAMES[$i]}"
    
    echo -n "  Deploying key to $name..."
    
    # Try with both the default password and without (in case key is already there)
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        -i "$SSH_KEY" "pi@$ip" "echo 'Key works'" &>/dev/null; then
        echo -e " ${GREEN}✓ Already configured${NC}"
    else
        # Deploy key using default password
        sshpass -p "$DEFAULT_PASSWORD" ssh-copy-id \
            -o StrictHostKeyChecking=no \
            -i "${SSH_KEY}.pub" "pi@$ip" &>/dev/null || {
            echo -e " ${RED}✗ Failed${NC}"
            echo "    Could not deploy key to $name"
            echo "    Try manually: ssh-copy-id -i ${SSH_KEY}.pub pi@$ip"
            exit 1
        }
        echo -e " ${GREEN}✓ Deployed${NC}"
    fi
done

# Step 4: Configure SSH client
echo -e "\n${YELLOW}Step 4: Configuring SSH client...${NC}"
if ! grep -q "# Raspberry Pi Cluster" ~/.ssh/config 2>/dev/null; then
    cat >> ~/.ssh/config << EOF

# Raspberry Pi Cluster
Host pi-a
    HostName 10.0.1.10
    User pi
    IdentityFile $SSH_KEY
    StrictHostKeyChecking no

Host pi-b
    HostName 10.0.1.11
    User pi
    IdentityFile $SSH_KEY
    StrictHostKeyChecking no

Host pi-c
    HostName 10.0.1.12
    User pi
    IdentityFile $SSH_KEY
    StrictHostKeyChecking no

Host pi-d
    HostName 10.0.1.13
    User pi
    IdentityFile $SSH_KEY
    StrictHostKeyChecking no
EOF
    echo -e "  ${GREEN}✓ SSH config updated${NC}"
else
    echo -e "  ${GREEN}✓ SSH config already configured${NC}"
fi

# Step 5: Verify cloud-init completion
echo -e "\n${YELLOW}Step 5: Verifying cloud-init completion...${NC}"
for name in "${PI_NAMES[@]}"; do
    echo -n "  Checking $name..."
    
    if ssh "$name" "test -f /var/log/cloud-init-complete.log" 2>/dev/null; then
        echo -e " ${GREEN}✓ Complete${NC}"
    else
        echo -e " ${YELLOW}⚠ Still running${NC}"
        echo "    Cloud-init may still be running. Waiting..."
        sleep 30
    fi
done

# Step 6: Run health checks
echo -e "\n${YELLOW}Step 6: Running health checks...${NC}"
for name in "${PI_NAMES[@]}"; do
    echo -e "\n  ${name}:"
    ssh "$name" "/usr/local/bin/health-check.sh 2>/dev/null || echo 'Health check not found'" || {
        echo "    Basic info:"
        ssh "$name" "hostname -I && free -h | grep Mem && df -h / | tail -1"
    }
done

# Step 7: Verify time synchronization (CLAUDE.md requirement)
echo -e "\n${YELLOW}Step 7: Verifying time synchronization...${NC}"
for name in "${PI_NAMES[@]}"; do
    echo -n "  $name: "
    
    offset=$(ssh "$name" "chronyc tracking 2>/dev/null | grep 'System time' | awk '{print \$4}'" || echo "999")
    
    if (( $(echo "$offset < 0.1" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "${GREEN}✓ Synced (${offset}s offset)${NC}"
    else
        echo -e "${RED}✗ Not synced (${offset}s offset)${NC}"
        echo "    Run: ssh $name 'sudo chronyc makestep'"
    fi
done

# Step 8: Start monitoring services (on pi-a)
echo -e "\n${YELLOW}Step 8: Starting monitoring services on pi-a...${NC}"
ssh pi-a << 'EOSSH'
# Reload systemd to pick up Quadlet files
sudo systemctl daemon-reload

# Start services in order
for service in prometheus grafana loki node-exporter promtail; do
    if [ -f "/etc/containers/systemd/${service}.container" ]; then
        echo -n "  Starting $service..."
        sudo systemctl start "${service}.service" 2>/dev/null || true
        sleep 2
        
        if sudo systemctl is-active "${service}.service" &>/dev/null; then
            echo " ✓"
        else
            echo " ✗"
        fi
    fi
done

# Show running containers
echo "  Running containers:"
sudo podman ps --format "    {{.Names}}: {{.Status}}"
EOSSH

# Step 9: Start services on other nodes
echo -e "\n${YELLOW}Step 9: Starting services on worker nodes...${NC}"
for name in pi-b pi-c pi-d; do
    echo "  Starting services on $name..."
    ssh "$name" << 'EOSSH'
    sudo systemctl daemon-reload
    
    # Start node-exporter
    if [ -f "/etc/containers/systemd/node-exporter.container" ]; then
        sudo systemctl start node-exporter.service 2>/dev/null || true
    fi
    
    # Start promtail
    if [ -f "/etc/containers/systemd/promtail.container" ]; then
        sudo systemctl start promtail.service 2>/dev/null || true
    fi
    
    # Start Caddy on pi-b
    if [ "$(hostname)" = "pi-b" ] && [ -f "/etc/containers/systemd/caddy.container" ]; then
        sudo systemctl start caddy.service 2>/dev/null || true
    fi
    
    sudo podman ps --format "    {{.Names}}: {{.Status}}" 2>/dev/null || echo "    No containers running"
EOSSH
done

# Step 10: Final validation
echo -e "\n${YELLOW}Step 10: Final validation...${NC}"

# Test service endpoints
echo "  Testing service endpoints:"

echo -n "    Prometheus (pi-a:9090): "
if curl -sf -o /dev/null "http://10.0.1.10:9090/-/ready"; then
    echo -e "${GREEN}✓ Ready${NC}"
else
    echo -e "${RED}✗ Not ready${NC}"
fi

echo -n "    Grafana (pi-a:3000): "
if curl -sf -o /dev/null "http://10.0.1.10:3000/api/health"; then
    echo -e "${GREEN}✓ Ready${NC}"
else
    echo -e "${RED}✗ Not ready${NC}"
fi

echo -n "    Loki (pi-a:3100): "
if curl -sf -o /dev/null "http://10.0.1.10:3100/ready"; then
    echo -e "${GREEN}✓ Ready${NC}"
else
    echo -e "${RED}✗ Not ready${NC}"
fi

echo -n "    Caddy (pi-b:80): "
if curl -sf -o /dev/null "http://10.0.1.11/"; then
    echo -e "${GREEN}✓ Ready${NC}"
else
    echo -e "${RED}✗ Not ready${NC}"
fi

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}   Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Access services:"
echo "  Grafana:    http://10.0.1.10:3000 (admin/admin)"
echo "  Prometheus: http://10.0.1.10:9090"
echo "  Loki:       http://10.0.1.10:3100"
echo ""
echo "SSH to nodes:"
echo "  ssh pi-a  # Monitoring stack"
echo "  ssh pi-b  # Ingress/Caddy"
echo "  ssh pi-c  # Worker"
echo "  ssh pi-d  # Worker/Backup"
echo ""
echo -e "${YELLOW}Important next steps:${NC}"
echo "1. Change the default password on all nodes:"
echo "   for host in pi-a pi-b pi-c pi-d; do"
echo "     ssh \$host 'passwd'"
echo "   done"
echo ""
echo "2. Set up Grafana admin password:"
echo "   ssh pi-a 'sudo podman exec grafana grafana-cli admin reset-admin-password <NEW_PASSWORD>'"
echo ""
echo "3. Configure backup automation:"
echo "   ssh pi-d 'crontab -e' # Add backup script"
echo ""
echo -e "${GREEN}✓ Your Raspberry Pi cluster is ready!${NC}"