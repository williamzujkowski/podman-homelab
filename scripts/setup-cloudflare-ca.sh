#!/usr/bin/env bash
set -euo pipefail

# Cloudflare Origin CA Setup for Internal Services
# This script configures Cloudflare Origin certificates for the homelab

echo "=== Cloudflare Origin CA Setup ==="
echo ""
echo "This script will help you configure Cloudflare Origin CA certificates"
echo "for your internal homelab services."
echo ""

# Check if running from correct directory
if [ ! -f "ansible.cfg" ]; then
    echo "ERROR: Please run this script from the ansible directory"
    exit 1
fi

# Function to create certificate directory structure
setup_cert_dirs() {
    local host="$1"
    echo "Creating certificate directories on $host..."
    
    ansible "$host" -i inventories/prod/hosts.yml -m file -a \
        "path=/etc/ssl/cloudflare state=directory mode=0755 owner=root group=root" \
        --become
}

# Function to generate Cloudflare Origin certificate request
generate_cert_request() {
    cat << 'EOF'
=== Generate Cloudflare Origin Certificate ===

1. Go to: https://dash.cloudflare.com/
2. Select your domain: grenlan.com
3. Navigate to SSL/TLS > Origin Server
4. Click "Create Certificate"
5. Select:
   - Private key type: RSA (2048)
   - Hostnames:
     * *.grenlan.com
     * grenlan.com
     * *.homelab.grenlan.com
     * homelab.grenlan.com
   - Validity: 15 years
6. Click "Create"
7. Save the certificate and private key

EOF
}

# Function to deploy certificate to host
deploy_cert() {
    local host="$1"
    local cert_file="$2"
    local key_file="$3"
    
    echo "Deploying certificates to $host..."
    
    # Copy certificate
    ansible "$host" -i inventories/prod/hosts.yml -m copy -a \
        "src=$cert_file dest=/etc/ssl/cloudflare/origin.crt mode=0644 owner=root group=root" \
        --become
    
    # Copy private key
    ansible "$host" -i inventories/prod/hosts.yml -m copy -a \
        "src=$key_file dest=/etc/ssl/cloudflare/origin.key mode=0600 owner=root group=root" \
        --become
}

# Function to update Caddy configuration for Cloudflare certificates
update_caddy_config() {
    echo "Updating Caddy configuration for Cloudflare certificates..."
    
    cat > templates/caddy/Caddyfile-cloudflare.j2 << 'CADDY_EOF'
# Caddy Configuration with Cloudflare Origin Certificates
# Managed by Ansible

{
    admin :2019
    log {
        output stdout
        format json
        level INFO
    }
}

# Import Cloudflare Origin certificate
(tls_cloudflare) {
    tls /etc/ssl/cloudflare/origin.crt /etc/ssl/cloudflare/origin.key {
        client_auth {
            mode require_and_verify
            trusted_ca_cert_file /etc/ssl/cloudflare/cloudflare-ca.crt
        }
    }
}

# Internal services - only accessible from local network
(internal_only) {
    @external {
        not remote_ip 192.168.1.0/24
        not remote_ip 10.0.0.0/8
        not remote_ip 172.16.0.0/12
        not remote_ip 127.0.0.1/32
    }
    respond @external "Access denied" 403
}

# Prometheus
prometheus.homelab.grenlan.com {
    import tls_cloudflare
    import internal_only
    
    reverse_proxy 192.168.1.12:9090 {
        header_up Host {http.reverse_proxy.upstream.hostport}
    }
}

# Grafana
grafana.homelab.grenlan.com {
    import tls_cloudflare
    import internal_only
    
    reverse_proxy 192.168.1.12:3000 {
        header_up Host {http.reverse_proxy.upstream.hostport}
    }
}

# Loki
loki.homelab.grenlan.com {
    import tls_cloudflare
    import internal_only
    
    reverse_proxy 192.168.1.12:3100 {
        header_up Host {http.reverse_proxy.upstream.hostport}
    }
}

# Redirect base domain to Grafana
homelab.grenlan.com {
    import tls_cloudflare
    import internal_only
    
    redir https://grafana.homelab.grenlan.com{uri} permanent
}

# Health check endpoint (no auth required for internal monitoring)
:8080 {
    respond /health "OK" 200
    log {
        output stdout
        format json
    }
}
CADDY_EOF
    
    echo "Caddy configuration template created."
}

# Function to download Cloudflare CA certificate
download_cloudflare_ca() {
    echo "Downloading Cloudflare CA certificate..."
    
    # Cloudflare Origin CA root certificate
    curl -s https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem \
        -o /tmp/cloudflare-ca.crt
    
    echo "Cloudflare CA certificate downloaded."
}

# Function to configure DNS in /etc/hosts for local resolution
configure_local_dns() {
    local host="$1"
    
    echo "Configuring local DNS on $host..."
    
    ansible "$host" -i inventories/prod/hosts.yml -m blockinfile -a \
        "path=/etc/hosts \
         block='# Homelab services
192.168.1.12  prometheus.homelab.grenlan.com
192.168.1.12  grafana.homelab.grenlan.com
192.168.1.12  loki.homelab.grenlan.com
192.168.1.11  homelab.grenlan.com' \
         marker='# {mark} ANSIBLE MANAGED HOMELAB SERVICES'" \
        --become
}

# Main execution
main() {
    echo "=== Step 1: Generate Origin Certificate ==="
    generate_cert_request
    
    read -p "Have you generated the certificate? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Please generate the certificate first, then run this script again."
        exit 1
    fi
    
    echo ""
    read -p "Enter the path to your certificate file: " cert_file
    read -p "Enter the path to your private key file: " key_file
    
    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        echo "ERROR: Certificate or key file not found"
        exit 1
    fi
    
    echo ""
    echo "=== Step 2: Setup Certificate Directories ==="
    setup_cert_dirs "pi-b"  # Ingress node
    
    echo ""
    echo "=== Step 3: Download Cloudflare CA Certificate ==="
    download_cloudflare_ca
    
    echo ""
    echo "=== Step 4: Deploy Certificates ==="
    deploy_cert "pi-b" "$cert_file" "$key_file"
    
    # Deploy Cloudflare CA
    ansible "pi-b" -i inventories/prod/hosts.yml -m copy -a \
        "src=/tmp/cloudflare-ca.crt dest=/etc/ssl/cloudflare/cloudflare-ca.crt mode=0644 owner=root group=root" \
        --become
    
    echo ""
    echo "=== Step 5: Update Caddy Configuration ==="
    update_caddy_config
    
    echo ""
    echo "=== Step 6: Deploy Caddy Configuration ==="
    ansible "pi-b" -i inventories/prod/hosts.yml -m template -a \
        "src=templates/caddy/Caddyfile-cloudflare.j2 dest=/etc/caddy/Caddyfile backup=yes" \
        --become
    
    echo ""
    echo "=== Step 7: Configure Local DNS ==="
    for host in pi-a pi-b pi-c pi-d; do
        configure_local_dns "$host"
    done
    
    echo ""
    echo "=== Step 8: Restart Caddy ==="
    ansible "pi-b" -i inventories/prod/hosts.yml -m systemd -a \
        "name=caddy state=restarted" \
        --become
    
    echo ""
    echo "=== Setup Complete! ==="
    echo ""
    echo "Your services should now be accessible at:"
    echo "  - https://grafana.homelab.grenlan.com"
    echo "  - https://prometheus.homelab.grenlan.com"
    echo "  - https://loki.homelab.grenlan.com"
    echo ""
    echo "Note: These are only accessible from your local network."
    echo "Add these entries to your local machine's /etc/hosts:"
    echo "  192.168.1.11  homelab.grenlan.com"
    echo "  192.168.1.11  grafana.homelab.grenlan.com"
    echo "  192.168.1.11  prometheus.homelab.grenlan.com"
    echo "  192.168.1.11  loki.homelab.grenlan.com"
}

# Run main function
main "$@"