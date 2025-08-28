# Certificate Management Guide

## Overview
The Raspberry Pi cluster uses self-signed certificates for HTTPS encryption. All nodes have been configured with:
- Self-signed wildcard certificate for `*.grenlan.com`
- HTTP to HTTPS automatic redirection via Traefik
- Certificate validity: 10 years (expires August 25, 2035)

## Certificate Details

### Locations
- **Certificate**: `/etc/ssl/cluster/server.crt`
- **Private Key**: `/etc/ssl/cluster/server.key`
- **CA Certificate**: `/etc/ssl/cluster/ca.crt`
- **Full Chain**: `/etc/ssl/cluster/fullchain.pem`

### Coverage
The wildcard certificate covers:
- `*.grenlan.com`
- `pi-a.grenlan.com`, `pi-b.grenlan.com`, `pi-c.grenlan.com`, `pi-d.grenlan.com`
- `grafana.grenlan.com`, `prometheus.grenlan.com`, `traefik.grenlan.com`, `minio.grenlan.com`
- All node IP addresses (192.168.1.10-13)
- `localhost` and `127.0.0.1`

## Current Status

| Service | HTTPS Status | Access URL |
|---------|--------------|------------|
| Traefik | ✅ Enabled | https://pi-b.grenlan.com (port 443) |
| HTTP→HTTPS Redirect | ✅ Working | Automatic on port 80 |
| Grafana | ⏳ HTTP only | http://pi-a.grenlan.com:3000 |
| Prometheus | ⏳ HTTP only | http://pi-a.grenlan.com:9090 |
| MinIO | ⏳ HTTP only | http://pi-d.grenlan.com:9001 |

## Trust the CA Certificate

### On Your Local System

#### Linux/Ubuntu
```bash
# Copy CA certificate from any Pi node
scp pi@192.168.1.12:/etc/ssl/cluster/ca.crt ~/pi-cluster-ca.crt

# Add to system trust store
sudo cp ~/pi-cluster-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

#### macOS
```bash
# Copy CA certificate
scp pi@192.168.1.12:/etc/ssl/cluster/ca.crt ~/pi-cluster-ca.crt

# Add to Keychain
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/pi-cluster-ca.crt
```

#### Windows
1. Copy the CA certificate to your Windows machine
2. Double-click the `ca.crt` file
3. Click "Install Certificate"
4. Select "Local Machine" → "Place all certificates in the following store"
5. Browse and select "Trusted Root Certification Authorities"
6. Complete the wizard

### In Your Browser

#### Firefox
1. Settings → Privacy & Security → Certificates → View Certificates
2. Import → Select `ca.crt` file
3. Trust for websites

#### Chrome/Edge
Uses system certificate store (follow OS instructions above)

## Testing HTTPS

```bash
# Test HTTPS redirect
curl -I http://192.168.1.11
# Should return: HTTP/1.1 308 Permanent Redirect

# Test HTTPS connection (with self-signed cert)
curl -k https://192.168.1.11

# Test with CA verification (after importing CA cert)
curl --cacert /etc/ssl/cluster/ca.crt https://pi-b.grenlan.com
```

## DNS Configuration

To use the domain names, add these entries to your `/etc/hosts` file:

```bash
# Pi Cluster
192.168.1.12 pi-a.grenlan.com grafana.grenlan.com prometheus.grenlan.com
192.168.1.11 pi-b.grenlan.com traefik.grenlan.com
192.168.1.10 pi-c.grenlan.com
192.168.1.13 pi-d.grenlan.com minio.grenlan.com storage.grenlan.com
```

## Certificate Renewal

The certificates are valid until 2035. To regenerate them:

```bash
# Run on any Pi node
bash /tmp/generate-certs.sh

# Then restart services
ssh pi@192.168.1.11 "podman restart traefik"
```

## Ansible Integration

The certificate role has been created at `ansible/roles/certificates/` with:
- Automated certificate generation
- Service configuration for TLS
- Trust store management

To redeploy certificates via Ansible:
```bash
ansible-playbook -i inventories/prod/hosts.yml playbooks/50-certificates.yml
```

## Troubleshooting

### Certificate Errors
- **"SSL_UNRECOGNIZED_NAME_ALERT"**: SNI issue, use IP address or configure DNS
- **"Certificate not trusted"**: Import the CA certificate to your system
- **"Connection refused on 443"**: Check if Traefik is running

### Verify Certificate
```bash
# Check certificate details
openssl x509 -in /etc/ssl/cluster/server.crt -text -noout

# Verify certificate chain
openssl verify -CAfile /etc/ssl/cluster/ca.crt /etc/ssl/cluster/server.crt

# Test TLS connection
openssl s_client -connect 192.168.1.11:443 -servername pi-b.grenlan.com
```

## Next Steps

1. **Import CA Certificate**: Add `/etc/ssl/cluster/ca.crt` to your browser/system
2. **Configure DNS**: Update `/etc/hosts` or local DNS server
3. **Enable HTTPS for Services**: Configure Grafana and Prometheus to use certificates
4. **Setup Certificate Monitoring**: Add expiry alerts to monitoring stack