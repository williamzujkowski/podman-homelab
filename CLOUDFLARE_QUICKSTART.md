# Cloudflare Setup Quick Start

## ✅ What We've Done
1. Installed @ironclads/cloudflare-mcp server
2. Added MCP server to Claude configuration
3. Created setup scripts and documentation

## 📋 Next Steps (Do These Now)

### 1. Get Your Cloudflare API Token
```bash
# Run the setup script
./cloudflare-mcp-setup.sh
```
Follow the prompts to:
- Create API token at https://dash.cloudflare.com/profile/api-tokens
- Enter the token when prompted
- Script will update your configuration

### 2. Restart Claude Desktop
- Close Claude Desktop completely
- Reopen it to load the new MCP server

### 3. Run Automatic Configuration
Once Claude restarts with the MCP server, ask me to:
```
"Please use the Cloudflare MCP tools to:
1. List and clean up old DNS records
2. Add homelab subdomain records  
3. Configure SSL to Full (strict)
4. Set up security rules
5. Enable all security features"
```

### 4. Deploy Origin Certificate to Traefik
After DNS is configured:
```bash
# Generate certificate in Cloudflare dashboard
# Then run:
./cloudflare-origin-setup.sh
```

### 5. Validate Everything
```bash
# Test all configurations
./validate-cloudflare.sh
```

## 🚀 What You'll Get

After setup:
- ✅ All services at https://*.homelab.grenlan.com
- ✅ Home IP completely hidden
- ✅ DDoS protection
- ✅ WAF and bot protection
- ✅ 15-year SSL certificates
- ✅ Global CDN performance
- ✅ Real-time threat blocking

## 🔧 Available MCP Tools

Once connected, I can use these tools:
- `list_dns_records` - View all DNS records
- `create_dns_record` - Add new records
- `delete_dns_record` - Remove old records
- `update_ssl_mode` - Set SSL to Full (strict)
- `create_firewall_rule` - Add security rules
- `update_zone_setting` - Configure security settings
- `purge_cache` - Clear CDN cache

## ⚠️ Important Notes

1. **DO NOT** delete the MX record if you might use email later
2. **KEEP** the root A record (grenlan.com → GitHub Pages)
3. **TEST** locally before enabling strict security rules
4. **BACKUP** your API token securely

## 📊 Monitoring

After setup, monitor at:
- https://dash.cloudflare.com/[your-account]/grenlan.com/analytics
- Check Firewall Events for blocked threats
- Review Traffic Analytics
- Monitor SSL certificate status

Ready to start? Run `./cloudflare-mcp-setup.sh` first!