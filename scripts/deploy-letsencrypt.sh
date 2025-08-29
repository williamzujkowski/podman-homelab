#!/usr/bin/env bash

# Deploy Let's Encrypt configuration to Traefik
# Usage: ./deploy-letsencrypt.sh <email> <cloudflare-api-token>

set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 <email> <cloudflare-api-token>"
    echo ""
    echo "Example: $0 admin@example.com your-cloudflare-token"
    echo ""
    echo "Create API token at: https://dash.cloudflare.com/profile/api-tokens"
    echo "Required permissions: Zone:DNS:Edit and Zone:Zone:Read"
    exit 1
fi

ACME_EMAIL="$1"
CLOUDFLARE_API_TOKEN="$2"
TRAEFIK_HOST="192.168.1.11"

echo "=== Deploying Let's Encrypt Configuration ==="
echo "Email: $ACME_EMAIL"
echo "Target: $TRAEFIK_HOST"
echo ""

# Create environment file
cat > /tmp/cloudflare-env << EOF
CF_DNS_API_TOKEN=$CLOUDFLARE_API_TOKEN
CLOUDFLARE_DNS_API_TOKEN=$CLOUDFLARE_API_TOKEN
CLOUDFLARE_API_TOKEN=$CLOUDFLARE_API_TOKEN
EOF

# Update email in config
sed "s/admin@grenlan.com/$ACME_EMAIL/g" ../ansible/templates/traefik/traefik-letsencrypt.yml > /tmp/traefik.yml

# Deploy to server
echo "Deploying configuration..."
scp /tmp/cloudflare-env pi@${TRAEFIK_HOST}:/tmp/cloudflare-env
scp /tmp/traefik.yml pi@${TRAEFIK_HOST}:/tmp/traefik.yml
scp ../ansible/templates/traefik/homelab-routes-letsencrypt.yml pi@${TRAEFIK_HOST}:/tmp/homelab-routes.yml

ssh pi@${TRAEFIK_HOST} << 'ENDSSH'
# Deploy files
sudo mv /tmp/cloudflare-env /etc/traefik/cloudflare-env
sudo chmod 600 /etc/traefik/cloudflare-env
sudo chown root:root /etc/traefik/cloudflare-env

sudo cp /etc/traefik/traefik.yml /etc/traefik/traefik.yml.bak
sudo mv /tmp/traefik.yml /etc/traefik/traefik.yml
sudo mv /tmp/homelab-routes.yml /etc/traefik/dynamic/homelab-routes.yml

# Create ACME storage
sudo touch /etc/traefik/acme.json
sudo chmod 600 /etc/traefik/acme.json

# Restart Traefik with new environment
podman stop systemd-traefik 2>/dev/null || true
podman rm systemd-traefik 2>/dev/null || true

podman run -d \
    --name systemd-traefik \
    --env-file /etc/traefik/cloudflare-env \
    -p 80:80 \
    -p 443:443 \
    -p 8080:8080 \
    -v /etc/traefik:/etc/traefik:z \
    -v /var/log/traefik:/var/log/traefik:z \
    --restart always \
    docker.io/library/traefik:v3.1
ENDSSH

rm -f /tmp/cloudflare-env /tmp/traefik.yml

echo ""
echo "Deployment complete! Monitor certificate generation:"
echo "ssh pi@${TRAEFIK_HOST} 'podman logs -f systemd-traefik 2>&1 | grep -i acme'"