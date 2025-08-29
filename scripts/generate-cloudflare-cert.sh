#!/usr/bin/env bash
set -euo pipefail

# Generate Cloudflare Origin CA Certificate for homelab.grenlan.com
# This script helps generate the certificate request for Cloudflare

echo "=== Cloudflare Origin CA Certificate Generator ==="
echo ""
echo "This script will help you generate a Cloudflare Origin CA certificate"
echo "for your homelab infrastructure."
echo ""

# Check if user has API key
echo "To automate certificate generation, we need your Cloudflare API credentials."
echo ""
read -p "Do you have a Cloudflare API key? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Please provide your Cloudflare credentials:"
    read -p "Enter your Cloudflare email: " CF_EMAIL
    read -sp "Enter your Cloudflare API Key: " CF_API_KEY
    echo ""
    
    # Generate certificate using API
    echo ""
    echo "Generating certificate via Cloudflare API..."
    
    # Create the certificate request
    HOSTNAMES='["*.homelab.grenlan.com","homelab.grenlan.com","*.grenlan.com","grenlan.com"]'
    
    # Call Cloudflare API
    RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/certificates" \
         -H "X-Auth-Email: $CF_EMAIL" \
         -H "X-Auth-Key: $CF_API_KEY" \
         -H "Content-Type: application/json" \
         --data "{\"hostnames\":$HOSTNAMES,\"requested_validity\":5475,\"request_type\":\"origin-rsa\"}")
    
    # Check if successful
    if echo "$RESPONSE" | grep -q '"success":true'; then
        echo "✅ Certificate generated successfully!"
        
        # Extract certificate and key
        CERT=$(echo "$RESPONSE" | grep -Po '"certificate":"\K[^"]*' | sed 's/\\n/\n/g')
        KEY=$(echo "$RESPONSE" | grep -Po '"private_key":"\K[^"]*' | sed 's/\\n/\n/g')
        
        # Save to files
        echo "$CERT" > /tmp/cloudflare-origin.crt
        echo "$KEY" > /tmp/cloudflare-origin.key
        
        echo ""
        echo "Certificate saved to: /tmp/cloudflare-origin.crt"
        echo "Private key saved to: /tmp/cloudflare-origin.key"
        echo ""
        
        # Download Cloudflare CA root
        echo "Downloading Cloudflare CA root certificate..."
        curl -s https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem \
            -o /tmp/cloudflare-ca.crt
        
        echo "CA certificate saved to: /tmp/cloudflare-ca.crt"
        echo ""
        
        # Create bundle
        cat /tmp/cloudflare-origin.crt /tmp/cloudflare-ca.crt > /tmp/cloudflare-fullchain.pem
        echo "Full chain created at: /tmp/cloudflare-fullchain.pem"
        echo ""
        
        echo "=== Next Steps ==="
        echo "1. Deploy certificates to pi-b (ingress):"
        echo "   scp /tmp/cloudflare-*.{crt,key,pem} pi@192.168.1.11:/tmp/"
        echo ""
        echo "2. Install on pi-b:"
        echo "   ssh pi@192.168.1.11"
        echo "   sudo mkdir -p /etc/ssl/cloudflare"
        echo "   sudo cp /tmp/cloudflare-origin.crt /etc/ssl/cloudflare/"
        echo "   sudo cp /tmp/cloudflare-origin.key /etc/ssl/cloudflare/"
        echo "   sudo cp /tmp/cloudflare-fullchain.pem /etc/ssl/cloudflare/"
        echo "   sudo chmod 600 /etc/ssl/cloudflare/cloudflare-origin.key"
        echo ""
        echo "3. Update Traefik to use new certificates"
        
    else
        echo "❌ Failed to generate certificate"
        echo "Error: $RESPONSE"
        exit 1
    fi
else
    echo ""
    echo "=== Manual Certificate Generation ==="
    echo ""
    echo "Please follow these steps to manually generate a certificate:"
    echo ""
    echo "1. Go to: https://dash.cloudflare.com/"
    echo "2. Select your domain: grenlan.com"
    echo "3. Navigate to: SSL/TLS → Origin Server"
    echo "4. Click 'Create Certificate'"
    echo "5. Configure as follows:"
    echo ""
    echo "   Hostnames (add all of these):"
    echo "   - *.homelab.grenlan.com"
    echo "   - homelab.grenlan.com"  
    echo "   - *.grenlan.com"
    echo "   - grenlan.com"
    echo ""
    echo "   Private key type: RSA (2048)"
    echo "   Certificate validity: 15 years"
    echo ""
    echo "6. Click 'Create'"
    echo "7. Save both the certificate and private key"
    echo ""
    echo "8. Save files as:"
    echo "   - Certificate: /tmp/cloudflare-origin.crt"
    echo "   - Private Key: /tmp/cloudflare-origin.key"
    echo ""
    echo "9. Download CA root:"
    echo "   curl -s https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem \\"
    echo "        -o /tmp/cloudflare-ca.crt"
    echo ""
    echo "10. Create full chain:"
    echo "    cat /tmp/cloudflare-origin.crt /tmp/cloudflare-ca.crt > /tmp/cloudflare-fullchain.pem"
fi