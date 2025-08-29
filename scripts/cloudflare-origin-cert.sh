#!/usr/bin/env bash
set -euo pipefail

# Cloudflare Origin CA Certificate Generator with proper CSR
# This script generates a CSR and requests a certificate from Cloudflare

echo "=== Cloudflare Origin CA Certificate Setup ==="
echo ""
echo "This script will generate a proper CSR and request a certificate from Cloudflare"
echo ""

# Function to generate CSR
generate_csr() {
    echo "Generating Certificate Signing Request (CSR)..."
    
    # Create temporary OpenSSL config
    cat > /tmp/openssl.cnf << 'EOF'
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=US
ST=State
L=City
O=Homelab
CN=*.homelab.grenlan.com

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.homelab.grenlan.com
DNS.2 = homelab.grenlan.com
DNS.3 = *.grenlan.com
DNS.4 = grenlan.com
DNS.5 = grafana.homelab.grenlan.com
DNS.6 = prometheus.homelab.grenlan.com
DNS.7 = loki.homelab.grenlan.com
EOF
    
    # Generate private key
    openssl genrsa -out /tmp/origin.key 2048 2>/dev/null
    
    # Generate CSR
    openssl req -new -key /tmp/origin.key -out /tmp/origin.csr -config /tmp/openssl.cnf 2>/dev/null
    
    # Read CSR for API
    CSR=$(cat /tmp/origin.csr | sed ':a;N;$!ba;s/\n/\\n/g')
    
    echo "✅ CSR generated successfully"
}

# Function to request certificate from Cloudflare
request_certificate() {
    local api_token="$1"
    
    echo "Requesting certificate from Cloudflare..."
    
    # Prepare the CSR for JSON
    local csr_content=$(cat /tmp/origin.csr)
    
    # Create JSON payload with proper escaping
    local json_payload=$(cat <<EOF
{
    "hostnames": ["*.homelab.grenlan.com", "homelab.grenlan.com", "*.grenlan.com", "grenlan.com"],
    "requested_validity": 5475,
    "request_type": "origin-rsa",
    "csr": "$CSR"
}
EOF
)
    
    # Make API call
    local response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/certificates" \
         -H "Authorization: Bearer $api_token" \
         -H "Content-Type: application/json" \
         --data "$json_payload")
    
    # Check response
    if echo "$response" | grep -q '"success":true'; then
        echo "✅ Certificate received from Cloudflare!"
        
        # Extract certificate
        echo "$response" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data.get('success'):
    cert = data['result']['certificate']
    with open('/tmp/cloudflare-origin.crt', 'w') as f:
        f.write(cert)
    print('Certificate saved to /tmp/cloudflare-origin.crt')
else:
    print('Error:', data.get('errors', 'Unknown error'))
    sys.exit(1)
"
        
        # We already have the private key from CSR generation
        cp /tmp/origin.key /tmp/cloudflare-origin.key
        
        return 0
    else
        echo "❌ Failed to get certificate"
        echo "Response: $response" | head -200
        return 1
    fi
}

# Function to deploy certificates
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
        
        # Restart Traefik
        echo "Restarting Traefik..."
        podman restart traefik
        
        echo "✅ Certificates deployed!"
EOF
    
    # Clean up
    rm -f /tmp/cloudflare-* /tmp/origin.* /tmp/openssl.cnf
    
    echo "✅ Deployment complete!"
}

# Main function
main() {
    # Check prerequisites
    if ! command -v openssl &> /dev/null; then
        echo "❌ OpenSSL is required but not installed"
        exit 1
    fi
    
    if ! command -v python3 &> /dev/null; then
        echo "❌ Python3 is required but not installed"
        exit 1
    fi
    
    # Get API token
    read -sp "Enter your Cloudflare API Token: " CF_API_TOKEN
    echo ""
    echo ""
    
    # Generate CSR
    generate_csr
    
    # Request certificate
    if request_certificate "$CF_API_TOKEN"; then
        # Deploy to pi-b
        deploy_certificates
        
        echo ""
        echo "=== Testing HTTPS Access ==="
        
        # Test access
        for domain in homelab.grenlan.com grafana.homelab.grenlan.com; do
            echo -n "Testing $domain... "
            code=$(curl -k -s -o /dev/null -w "%{http_code}" "https://$domain" 2>/dev/null || echo "000")
            if [[ "$code" == "200" ]] || [[ "$code" == "302" ]] || [[ "$code" == "301" ]]; then
                echo "✅ OK ($code)"
            else
                echo "❌ Failed ($code)"
            fi
        done
        
        echo ""
        echo "=== Setup Complete! ==="
        echo ""
        echo "You can now access your services at:"
        echo "  • https://grafana.homelab.grenlan.com"
        echo "  • https://prometheus.homelab.grenlan.com"
        echo "  • https://loki.homelab.grenlan.com"
    else
        echo ""
        echo "Please check your API token and try again"
        echo ""
        echo "Make sure your token has permission: Zone → SSL and Certificates → Edit"
        exit 1
    fi
}

# Run main
main "$@"