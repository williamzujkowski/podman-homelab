#!/usr/bin/env bash

# Setup Certbot with Cloudflare DNS-01 Challenge
# This script installs certbot and generates Let's Encrypt certificates
# independently from Traefik

set -e

CLOUDFLARE_API_TOKEN="${1:-}"
EMAIL="${2:-grenlan@gmail.com}"
TRAEFIK_HOST="192.168.1.11"

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo "Usage: $0 <cloudflare-api-token> [email]"
    echo ""
    echo "Example: $0 your-api-token admin@example.com"
    exit 1
fi

echo "=== Setting up Certbot with Cloudflare DNS-01 ==="
echo "Target host: $TRAEFIK_HOST"
echo "Email: $EMAIL"
echo ""

# Create the setup script that will run on pi-b
cat > /tmp/certbot-setup.sh << 'EOSCRIPT'
#!/bin/bash
set -e

echo "Installing certbot and dependencies..."

# Update package list
sudo apt-get update

# Install certbot and python3-pip
sudo apt-get install -y certbot python3-pip python3-venv

# Create virtual environment for certbot plugins
sudo python3 -m venv /opt/certbot-env

# Install Cloudflare DNS plugin in virtual environment
sudo /opt/certbot-env/bin/pip install certbot-dns-cloudflare

# Create certbot configuration directory
sudo mkdir -p /etc/letsencrypt

echo "Certbot installation complete."
EOSCRIPT

# Copy and execute the setup script on pi-b
echo "Installing certbot on $TRAEFIK_HOST..."
scp /tmp/certbot-setup.sh pi@${TRAEFIK_HOST}:/tmp/
ssh pi@${TRAEFIK_HOST} "chmod +x /tmp/certbot-setup.sh && /tmp/certbot-setup.sh"

# Create Cloudflare credentials file
echo "Setting up Cloudflare credentials..."
cat > /tmp/cloudflare.ini << EOF
# Cloudflare API credentials for certbot
dns_cloudflare_api_token = $CLOUDFLARE_API_TOKEN
EOF

# Deploy credentials to pi-b
scp /tmp/cloudflare.ini pi@${TRAEFIK_HOST}:/tmp/
ssh pi@${TRAEFIK_HOST} << 'ENDSSH'
sudo mkdir -p /etc/letsencrypt
sudo mv /tmp/cloudflare.ini /etc/letsencrypt/cloudflare.ini
sudo chmod 600 /etc/letsencrypt/cloudflare.ini
sudo chown root:root /etc/letsencrypt/cloudflare.ini
ENDSSH

# Create certificate generation script
cat > /tmp/generate-certs.sh << EOSCRIPT
#!/bin/bash
set -e

EMAIL="$EMAIL"

echo "Generating Let's Encrypt certificates..."

# Generate certificates for all our domains
# Using --dry-run first to test
sudo /opt/certbot-env/bin/certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  --email \$EMAIL \
  --agree-tos \
  --non-interactive \
  --dry-run \
  -d "homelab.grenlan.com" \
  -d "*.homelab.grenlan.com" \
  -d "grafana.homelab.grenlan.com" \
  -d "prometheus.homelab.grenlan.com" \
  -d "loki.homelab.grenlan.com"

echo ""
echo "Dry run successful! Now generating real certificates..."

# Generate real certificates
sudo /opt/certbot-env/bin/certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  --email \$EMAIL \
  --agree-tos \
  --non-interactive \
  -d "homelab.grenlan.com" \
  -d "*.homelab.grenlan.com" \
  -d "grafana.homelab.grenlan.com" \
  -d "prometheus.homelab.grenlan.com" \
  -d "loki.homelab.grenlan.com"

echo "Certificates generated successfully!"

# Set permissions for Traefik access
sudo chmod 755 /etc/letsencrypt/live
sudo chmod 755 /etc/letsencrypt/archive

echo "Certificate locations:"
sudo ls -la /etc/letsencrypt/live/homelab.grenlan.com/
EOSCRIPT

# Copy and run certificate generation
echo "Generating certificates..."
scp /tmp/generate-certs.sh pi@${TRAEFIK_HOST}:/tmp/
ssh pi@${TRAEFIK_HOST} "chmod +x /tmp/generate-certs.sh && /tmp/generate-certs.sh"

# Create auto-renewal systemd service and timer
cat > /tmp/certbot-renew.service << 'EOSCRIPT'
[Unit]
Description=Certbot Renewal
After=network.target

[Service]
Type=oneshot
ExecStart=/opt/certbot-env/bin/certbot renew --dns-cloudflare --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini --deploy-hook "podman restart systemd-traefik"
User=root

[Install]
WantedBy=multi-user.target
EOSCRIPT

cat > /tmp/certbot-renew.timer << 'EOSCRIPT'
[Unit]
Description=Run certbot renewal twice daily
Requires=certbot-renew.service

[Timer]
OnCalendar=*-*-* 00,12:00:00
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOSCRIPT

# Deploy systemd units
echo "Setting up auto-renewal..."
scp /tmp/certbot-renew.service /tmp/certbot-renew.timer pi@${TRAEFIK_HOST}:/tmp/
ssh pi@${TRAEFIK_HOST} << 'ENDSSH'
sudo mv /tmp/certbot-renew.service /etc/systemd/system/
sudo mv /tmp/certbot-renew.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable certbot-renew.timer
sudo systemctl start certbot-renew.timer

echo "Auto-renewal timer status:"
sudo systemctl status certbot-renew.timer --no-pager
ENDSSH

# Clean up temp files
rm -f /tmp/certbot-setup.sh /tmp/cloudflare.ini /tmp/generate-certs.sh /tmp/certbot-renew.*

echo ""
echo "=== Certbot Setup Complete ==="
echo ""
echo "Certificates are stored in: /etc/letsencrypt/live/homelab.grenlan.com/"
echo "Auto-renewal is configured to run twice daily"
echo ""
echo "Next step: Update Traefik configuration to use these certificates"