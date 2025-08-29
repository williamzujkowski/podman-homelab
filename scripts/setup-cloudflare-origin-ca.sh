#!/usr/bin/env bash
set -euo pipefail

# Secure Cloudflare Origin CA Certificate Setup
# This script generates and deploys certificates without storing credentials

echo "=== Cloudflare Origin CA Certificate Setup ==="
echo ""
echo "This script will generate and deploy Cloudflare Origin certificates"
echo "Your credentials will only be used for this session and not stored."
echo ""

# Function to generate certificate via API with email auth
generate_certificate() {
    local email="$1"
    local api_key="$2"
    
    echo "Generating certificate via Cloudflare API (email auth)..."
    
    # Certificate request for all domains
    local hostnames='["*.homelab.grenlan.com","homelab.grenlan.com","*.grenlan.com","grenlan.com"]'
    
    # Call Cloudflare API
    local response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/certificates" \
         -H "X-Auth-Email: $email" \
         -H "X-Auth-Key: $api_key" \
         -H "Content-Type: application/json" \
         --data "{
             \"hostnames\": $hostnames,
             \"requested_validity\": 5475,
             \"request_type\": \"origin-rsa\"
         }")
    
    # Check if successful
    if echo "$response" | grep -q '"success":true'; then
        echo "✅ Certificate generated successfully!"
        
        # Extract certificate and key using python for reliable JSON parsing
        echo "$response" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data.get('success'):
    cert = data['result']['certificate']
    key = data['result']['private_key']
    
    # Save certificate
    with open('/tmp/cloudflare-origin.crt', 'w') as f:
        f.write(cert)
    
    # Save key
    with open('/tmp/cloudflare-origin.key', 'w') as f:
        f.write(key)
    
    print('Certificate and key extracted successfully')
else:
    print('Error:', data.get('errors', 'Unknown error'))
    sys.exit(1)
"
        return 0
    else
        echo "❌ Failed to generate certificate"
        echo "Response: $response" | head -100
        return 1
    fi
}

# Function to deploy certificates to pi-b
deploy_certificates() {
    echo ""
    echo "=== Deploying Certificates to pi-b ==="
    
    # Download Cloudflare CA root
    echo "Downloading Cloudflare CA root certificate..."
    curl -s https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem \
        -o /tmp/cloudflare-ca.crt
    
    # Create full chain
    cat /tmp/cloudflare-origin.crt /tmp/cloudflare-ca.crt > /tmp/cloudflare-fullchain.pem
    
    echo "Copying certificates to pi-b (192.168.1.11)..."
    
    # Copy to pi-b
    scp /tmp/cloudflare-origin.crt /tmp/cloudflare-origin.key /tmp/cloudflare-fullchain.pem /tmp/cloudflare-ca.crt pi@192.168.1.11:/tmp/
    
    # Install on pi-b
    ssh pi@192.168.1.11 << 'EOF'
        echo "Installing certificates..."
        sudo mkdir -p /etc/ssl/cloudflare
        sudo cp /tmp/cloudflare-origin.crt /etc/ssl/cloudflare/
        sudo cp /tmp/cloudflare-origin.key /etc/ssl/cloudflare/
        sudo cp /tmp/cloudflare-fullchain.pem /etc/ssl/cloudflare/
        sudo cp /tmp/cloudflare-ca.crt /etc/ssl/cloudflare/
        
        # Set permissions
        sudo chmod 644 /etc/ssl/cloudflare/*.crt
        sudo chmod 644 /etc/ssl/cloudflare/*.pem
        sudo chmod 600 /etc/ssl/cloudflare/*.key
        sudo chown root:root /etc/ssl/cloudflare/*
        
        # Update Traefik TLS configuration
        echo "Updating Traefik configuration..."
        sudo tee /etc/traefik/dynamic/tls-cloudflare.yml > /dev/null << 'TRAEFIK'
tls:
  certificates:
    - certFile: /etc/ssl/cloudflare/cloudflare-fullchain.pem
      keyFile: /etc/ssl/cloudflare/cloudflare-origin.key
      stores:
        - default
  stores:
    default:
      defaultCertificate:
        certFile: /etc/ssl/cloudflare/cloudflare-fullchain.pem
        keyFile: /etc/ssl/cloudflare/cloudflare-origin.key
TRAEFIK
        
        # Restart Traefik to load new certificates
        echo "Restarting Traefik..."
        podman restart traefik
        
        echo "✅ Certificates deployed successfully!"
        
        # Verify certificate
        echo ""
        echo "Verifying certificate installation..."
        sudo openssl x509 -in /etc/ssl/cloudflare/cloudflare-origin.crt -text -noout | grep -E "Subject:|DNS:" | head -5
EOF
    
    # Clean up local temp files
    echo ""
    echo "Cleaning up temporary files..."
    rm -f /tmp/cloudflare-*.{crt,key,pem}
    
    echo "✅ Setup complete!"
}

# Function to test HTTPS access
test_access() {
    echo ""
    echo "=== Testing HTTPS Access ==="
    
    local domains=(
        "homelab.grenlan.com"
        "grafana.homelab.grenlan.com"
        "prometheus.homelab.grenlan.com"
        "loki.homelab.grenlan.com"
    )
    
    for domain in "${domains[@]}"; do
        echo -n "Testing $domain... "
        if curl -k -s -o /dev/null -w "%{http_code}" "https://$domain" | grep -q "200\|301\|302"; then
            echo "✅ OK"
        else
            echo "❌ Failed ($(curl -k -s -o /dev/null -w "%{http_code}" "https://$domain"))"
        fi
    done
}

# Main execution
main() {
    # Check prerequisites
    if ! command -v python3 &> /dev/null; then
        echo "❌ Python3 is required but not installed"
        exit 1
    fi
    
    if ! command -v scp &> /dev/null; then
        echo "❌ scp is required but not installed"
        exit 1
    fi
    
    # Get credentials
    echo "Please select your authentication method:"
    echo "1) API Token (recommended - no email needed)"
    echo "2) Global API Key (legacy - requires email)"
    echo ""
    read -p "Choice [1/2]: " auth_choice
    echo ""
    
    if [[ "$auth_choice" == "2" ]]; then
        # Legacy Global API Key
        read -p "Cloudflare account email: " CF_EMAIL
        read -sp "Cloudflare Global API Key: " CF_API_KEY
        echo ""
        echo ""
        
        # Generate certificate with email auth
        if generate_certificate "$CF_EMAIL" "$CF_API_KEY"; then
            # Deploy to pi-b
            deploy_certificates
            
            # Test access
            test_access
            
            echo ""
            echo "=== Setup Complete! ==="
            echo ""
            echo "You can now access your services at:"
            echo "  • https://grafana.homelab.grenlan.com"
            echo "  • https://prometheus.homelab.grenlan.com"
            echo "  • https://loki.homelab.grenlan.com"
            echo ""
            echo "Note: Certificates are valid for 15 years (until ~2040)"
        else
            echo ""
            echo "❌ Certificate generation failed"
            echo "Please check your credentials and try again"
            exit 1
        fi
    else
        # Modern API Token
        read -sp "Cloudflare API Token: " CF_API_TOKEN
        echo ""
        echo ""
        
        # Generate certificate with token auth
        if generate_certificate_token "$CF_API_TOKEN"; then
            # Deploy to pi-b
            deploy_certificates
            
            # Test access
            test_access
            
            echo ""
            echo "=== Setup Complete! ==="
            echo ""
            echo "You can now access your services at:"
            echo "  • https://grafana.homelab.grenlan.com"
            echo "  • https://prometheus.homelab.grenlan.com"
            echo "  • https://loki.homelab.grenlan.com"
            echo ""
            echo "Note: Certificates are valid for 15 years (until ~2040)"
        else
            echo ""
            echo "❌ Certificate generation failed"
            echo "Please check your API token and try again"
            exit 1
        fi
    fi
}

# Function to generate certificate via API with token auth
generate_certificate_token() {
    local api_token="$1"
    
    echo "Generating certificate via Cloudflare API (token auth)..."
    
    # Certificate request for all domains
    local hostnames='["*.homelab.grenlan.com","homelab.grenlan.com","*.grenlan.com","grenlan.com"]'
    
    # Call Cloudflare API with Bearer token
    local response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/certificates" \
         -H "Authorization: Bearer $api_token" \
         -H "Content-Type: application/json" \
         --data "{
             \"hostnames\": $hostnames,
             \"requested_validity\": 5475,
             \"request_type\": \"origin-rsa\"
         }")
    
    # Check if successful
    if echo "$response" | grep -q '"success":true'; then
        echo "✅ Certificate generated successfully!"
        
        # Extract certificate and key using python for reliable JSON parsing
        echo "$response" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data.get('success'):
    cert = data['result']['certificate']
    key = data['result']['private_key']
    
    # Save certificate
    with open('/tmp/cloudflare-origin.crt', 'w') as f:
        f.write(cert)
    
    # Save key
    with open('/tmp/cloudflare-origin.key', 'w') as f:
        f.write(key)
    
    print('Certificate and key extracted successfully')
else:
    print('Error:', data.get('errors', 'Unknown error'))
    sys.exit(1)
"
        return 0
    else
        echo "❌ Failed to generate certificate"
        echo "Response: $response" | head -100
        return 1
    fi
}

# Run main function
main "$@"