#!/usr/bin/env bash

# Setup Let's Encrypt with Cloudflare DNS-01 challenge for Traefik
# This script configures Traefik to use Let's Encrypt for browser-trusted certificates

set -e

echo "=== Let's Encrypt Setup for Traefik ==="
echo ""

# Check if we have the Cloudflare API token
if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo "Please provide your Cloudflare API token with Zone:DNS:Edit permissions:"
    echo "You can create one at: https://dash.cloudflare.com/profile/api-tokens"
    echo ""
    echo "The token needs these permissions:"
    echo "  - Zone:DNS:Edit for your domain"
    echo "  - Zone:Zone:Read for your domain"
    echo ""
    read -sp "Cloudflare API Token: " CLOUDFLARE_API_TOKEN
    echo ""
fi

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo "Error: Cloudflare API token is required"
    exit 1
fi

# Get email for Let's Encrypt
read -p "Enter email for Let's Encrypt notifications: " ACME_EMAIL
if [ -z "$ACME_EMAIL" ]; then
    echo "Error: Email is required for Let's Encrypt"
    exit 1
fi

TRAEFIK_HOST="192.168.1.11"

echo ""
echo "Setting up Let's Encrypt with:"
echo "  - Email: $ACME_EMAIL"
echo "  - Traefik host: $TRAEFIK_HOST"
echo "  - DNS Provider: Cloudflare"
echo ""

# Create the environment file for Cloudflare credentials
echo "Creating Cloudflare credentials file..."
cat > /tmp/cloudflare-env << EOF
# Cloudflare API credentials for Let's Encrypt DNS-01 challenge
CF_API_EMAIL=$ACME_EMAIL
CF_DNS_API_TOKEN=$CLOUDFLARE_API_TOKEN
CLOUDFLARE_DNS_API_TOKEN=$CLOUDFLARE_API_TOKEN
CLOUDFLARE_API_TOKEN=$CLOUDFLARE_API_TOKEN
EOF

# Copy credentials to Traefik host
echo "Deploying credentials to Traefik host..."
scp /tmp/cloudflare-env pi@${TRAEFIK_HOST}:/tmp/cloudflare-env
ssh pi@${TRAEFIK_HOST} "sudo mkdir -p /etc/traefik && sudo mv /tmp/cloudflare-env /etc/traefik/cloudflare-env && sudo chmod 600 /etc/traefik/cloudflare-env && sudo chown root:root /etc/traefik/cloudflare-env"

# Update Traefik configuration with email
echo "Updating Traefik configuration..."
sed -i "s/admin@grenlan.com/$ACME_EMAIL/g" ../ansible/templates/traefik/traefik-letsencrypt.yml

# Deploy Traefik configuration
echo "Deploying Traefik configuration..."
scp ../ansible/templates/traefik/traefik-letsencrypt.yml pi@${TRAEFIK_HOST}:/tmp/traefik.yml
scp ../ansible/templates/traefik/homelab-routes-letsencrypt.yml pi@${TRAEFIK_HOST}:/tmp/homelab-routes.yml

ssh pi@${TRAEFIK_HOST} << 'ENDSSH'
# Backup existing configuration
sudo cp /etc/traefik/traefik.yml /etc/traefik/traefik.yml.backup-$(date +%Y%m%d-%H%M%S)
sudo cp /etc/traefik/dynamic/homelab-routes.yml /etc/traefik/dynamic/homelab-routes.yml.backup-$(date +%Y%m%d-%H%M%S) 2>/dev/null || true

# Deploy new configuration
sudo mv /tmp/traefik.yml /etc/traefik/traefik.yml
sudo mv /tmp/homelab-routes.yml /etc/traefik/dynamic/homelab-routes.yml
sudo chown root:root /etc/traefik/traefik.yml /etc/traefik/dynamic/homelab-routes.yml

# Create ACME storage file with correct permissions
sudo touch /etc/traefik/acme.json
sudo chmod 600 /etc/traefik/acme.json
sudo chown root:root /etc/traefik/acme.json

# Create log directory if it doesn't exist
sudo mkdir -p /var/log/traefik
sudo touch /var/log/traefik/traefik.log /var/log/traefik/access.log
ENDSSH

# Update Traefik container to include environment file
echo "Updating Traefik container configuration..."
ssh pi@${TRAEFIK_HOST} << 'ENDSSH'
# Check if Traefik is running as a container or systemd service
if podman ps | grep -q systemd-traefik; then
    echo "Updating Traefik container with environment variables..."
    
    # Stop the existing container
    podman stop systemd-traefik
    podman rm systemd-traefik
    
    # Start Traefik with environment file
    podman run -d \
        --name systemd-traefik \
        --env-file /etc/traefik/cloudflare-env \
        -p 80:80 \
        -p 443:443 \
        -p 8080:8080 \
        -v /etc/traefik:/etc/traefik:ro \
        -v /var/log/traefik:/var/log/traefik \
        --restart always \
        docker.io/library/traefik:v3.1
else
    echo "Traefik not found as container. Checking for systemd service..."
    if systemctl list-units --all | grep -q traefik.service; then
        echo "Please update the systemd service to include the environment file"
    fi
fi
ENDSSH

# Clean up
rm -f /tmp/cloudflare-env

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Traefik is now configured to use Let's Encrypt with Cloudflare DNS-01 challenge."
echo "It may take a few minutes for the certificates to be issued."
echo ""
echo "Monitor the certificate generation with:"
echo "  ssh pi@${TRAEFIK_HOST} 'sudo tail -f /var/log/traefik/traefik.log | grep -i acme'"
echo ""
echo "Check certificate status:"
echo "  ssh pi@${TRAEFIK_HOST} 'sudo cat /etc/traefik/acme.json | jq'"
echo ""
echo "Once certificates are issued, access your services at:"
echo "  - https://grafana.homelab.grenlan.com"
echo "  - https://prometheus.homelab.grenlan.com"
echo "  - https://homelab.grenlan.com"