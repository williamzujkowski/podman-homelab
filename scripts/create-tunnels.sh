#!/bin/bash
# Create SSH tunnels to access monitoring services on VMs

echo "Creating SSH tunnels to monitoring services..."

# Kill any existing tunnels
pkill -f "ssh.*-L.*vm-a"
pkill -f "ssh.*-L.*vm-b"
sleep 2

# Grafana on vm-a (local:3000 -> vm-a:3000)
echo "Creating tunnel for Grafana (localhost:3000 -> vm-a:3000)"
ssh -f -N -L 3000:localhost:3000 vm-a

# Prometheus on vm-a (local:9090 -> vm-a:9090)  
echo "Creating tunnel for Prometheus (localhost:9090 -> vm-a:9090)"
ssh -f -N -L 9090:localhost:9090 vm-a

# Loki on vm-a (local:3100 -> vm-a:3100)
echo "Creating tunnel for Loki (localhost:3100 -> vm-a:3100)"
ssh -f -N -L 3100:localhost:3100 vm-a

# Caddy on vm-b (local:8080 -> vm-b:80)
echo "Creating tunnel for Caddy ingress (localhost:8080 -> vm-b:80)"
ssh -f -N -L 8080:localhost:80 vm-b

echo ""
echo "SSH tunnels created! Services are now accessible at:"
echo "  - Grafana:    http://localhost:3000"
echo "  - Prometheus: http://localhost:9090"
echo "  - Loki:       http://localhost:3100"
echo "  - Caddy:      http://localhost:8080"
echo ""
echo "To stop tunnels, run: pkill -f 'ssh.*-L'"