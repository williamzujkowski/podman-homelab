#!/bin/bash

# Cloudflare MCP Server Setup Script
# This script helps configure your Cloudflare API token for the MCP server

echo "=== Cloudflare MCP Server Setup ==="
echo
echo "This script will help you configure the Cloudflare MCP server"
echo "to manage your DNS records, SSL certificates, and security settings."
echo
echo "Step 1: Create a Cloudflare API Token"
echo "--------------------------------------"
echo "1. Go to: https://dash.cloudflare.com/profile/api-tokens"
echo "2. Click 'Create Token'"
echo "3. Use the 'Edit zone DNS' template or create a custom token with:"
echo "   - Zone:Zone Settings:Edit"
echo "   - Zone:Zone:Edit"  
echo "   - Zone:DNS:Edit"
echo "   - Zone:SSL and Certificates:Edit"
echo "   - Zone:Firewall Services:Edit"
echo "   - Zone:Cache Purge:Purge"
echo "   - Include specific zone: grenlan.com"
echo "4. Copy the generated token"
echo
read -p "Enter your Cloudflare API token: " CF_TOKEN

# Update Claude configuration
CONFIG_FILE="/home/william/.config/claude/claude_desktop_config.json"
echo
echo "Updating Claude configuration..."

# Use jq if available, otherwise use sed
if command -v jq &> /dev/null; then
    jq --arg token "$CF_TOKEN" '.mcpServers.cloudflare.env.CF_API_TOKEN = $token' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
else
    sed -i "s/YOUR_CLOUDFLARE_API_TOKEN/$CF_TOKEN/" "$CONFIG_FILE"
fi

echo "✓ Configuration updated"

# Test the MCP server
echo
echo "Testing Cloudflare MCP server connection..."
cd /home/william/mcp-servers/cloudflare
export CF_API_TOKEN="$CF_TOKEN"
export LOG_LEVEL="DEBUG"

# Simple test to verify the server starts
timeout 5 node node_modules/@ironclads/cloudflare-mcp/dist/index.js 2>&1 | head -20

echo
echo "=== Setup Complete ==="
echo
echo "Next steps:"
echo "1. Restart Claude Desktop to load the new MCP server"
echo "2. The Cloudflare MCP server will be available with these tools:"
echo "   - DNS Management: list_dns_records, create_dns_record, delete_dns_record"
echo "   - SSL/TLS: get_ssl_settings, update_ssl_mode"
echo "   - Security: create_firewall_rule, list_firewall_rules"
echo "   - Zone Settings: get_zone_settings, update_zone_setting"
echo "   - Cache: purge_cache, toggle_dev_mode"
echo
echo "Your domains will be configured as:"
echo "   - grafana.homelab.grenlan.com"
echo "   - prometheus.homelab.grenlan.com"
echo "   - traefik.homelab.grenlan.com"
echo "   - minio.homelab.grenlan.com"
echo
echo "Security features to be enabled:"
echo "   - Cloudflare proxy (orange cloud)"
echo "   - SSL/TLS mode: Full (strict)"
echo "   - Always Use HTTPS"
echo "   - Bot protection"
echo "   - WAF rules"