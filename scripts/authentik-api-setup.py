#!/usr/bin/env python3
"""
Authentik API Setup Script
==========================
Uses API calls to configure Authentik ForwardAuth and OAuth2 providers
"""

import requests
import json
import time
import sys
import argparse
from urllib.parse import urljoin


class AuthentikAPI:
    def __init__(self, host, admin_password='ChangeMe123!'):
        self.host = host
        self.base_url = f"http://{host}"
        self.admin_password = admin_password
        self.session = requests.Session()
        self.token = None
        
    def authenticate(self):
        """Get authentication token"""
        print("🔐 Authenticating with Authentik...")
        
        # Try to get token by creating a token via admin user
        # First, we need to check if we can access the API
        try:
            response = self.session.get(f"{self.base_url}/api/v3/root/config/")
            if response.status_code == 200:
                print("✅ API is accessible")
                
                # For now, we'll use a known token or create one manually
                # This is a limitation of automated setup - tokens need to be created via UI
                print("⚠️  API token required for provider creation")
                print("📋 Manual step: Create API token in Authentik admin interface")
                print("   1. Go to Directory > Tokens")
                print("   2. Create new token with 'authentik Core' scope")
                print("   3. Copy the token and set AUTHENTIK_TOKEN environment variable")
                return False
            else:
                print(f"❌ API not accessible: {response.status_code}")
                return False
                
        except Exception as e:
            print(f"❌ Authentication failed: {e}")
            return False
    
    def get_flows(self):
        """Get available authorization flows"""
        try:
            response = self.session.get(f"{self.base_url}/api/v3/flows/instances/")
            if response.status_code == 200:
                flows = response.json()['results']
                auth_flow = None
                for flow in flows:
                    if 'authorization' in flow.get('slug', '').lower():
                        auth_flow = flow['pk']
                        break
                return auth_flow
        except Exception as e:
            print(f"Error getting flows: {e}")
        return None
    
    def create_proxy_provider(self):
        """Create proxy provider for ForwardAuth"""
        print("🔗 Creating proxy provider for ForwardAuth...")
        
        # This requires authenticated API access
        # For demo purposes, show the configuration
        provider_config = {
            "name": "traefik-forwardauth",
            "authorization_flow": "default-provider-authorization-explicit-consent",
            "mode": "forward_single",
            "external_host": "https://auth.homelab.grenlan.com",
            "internal_host": "http://192.168.1.13:9002",
            "internal_host_ssl_validation": False,
            "cookie_domain": "homelab.grenlan.com",
            "token_validity": "hours=24"
        }
        
        print("📋 Provider configuration:")
        print(json.dumps(provider_config, indent=2))
        return provider_config
    
    def create_oauth2_provider(self):
        """Create OAuth2 provider for Grafana"""
        print("🔗 Creating OAuth2 provider for Grafana...")
        
        oauth2_config = {
            "name": "grafana-oauth2",
            "client_id": "grafana",
            "authorization_flow": "default-provider-authorization-explicit-consent",
            "client_type": "confidential",
            "redirect_uris": "http://192.168.1.12:3000/login/generic_oauth\nhttps://grafana.homelab.grenlan.com/login/generic_oauth",
            "sub_mode": "hashed_user_id",
            "include_claims_in_id_token": True,
            "issuer_mode": "per_provider"
        }
        
        print("📋 OAuth2 configuration:")
        print(json.dumps(oauth2_config, indent=2))
        return oauth2_config
    
    def test_endpoints(self):
        """Test configured endpoints"""
        print("🧪 Testing endpoints...")
        
        endpoints = [
            ("ForwardAuth", f"{self.base_url}/outpost.goauthentik.io/auth/traefik"),
            ("OAuth2 Authorization", f"{self.base_url}/application/o/authorize/"),
            ("OAuth2 Token", f"{self.base_url}/application/o/token/"),
            ("OAuth2 UserInfo", f"{self.base_url}/application/o/userinfo/"),
        ]
        
        results = {}
        for name, url in endpoints:
            try:
                response = requests.get(url, timeout=5, allow_redirects=False)
                status = response.status_code
                if status in [200, 302, 401, 405]:  # Expected responses
                    results[name] = "✅ Working"
                elif status == 404:
                    results[name] = "❌ Not Found"
                else:
                    results[name] = f"❓ HTTP {status}"
            except Exception as e:
                results[name] = f"❌ Error: {str(e)[:50]}"
        
        print("\n🔍 Endpoint Test Results:")
        for name, result in results.items():
            print(f"  {name}: {result}")
        
        return results
    
    def generate_instructions(self):
        """Generate manual configuration instructions"""
        instructions = f"""
=================================================
AUTHENTIK MANUAL CONFIGURATION INSTRUCTIONS
=================================================

Base URL: {self.base_url}
Admin User: akadmin
Password: {self.admin_password}

STEP 1: Complete Initial Setup (if needed)
------------------------------------------
1. Open: {self.base_url}/if/flow/initial-setup/
2. Create admin user:
   - Username: akadmin
   - Name: authentik Default Admin
   - Email: admin@homelab.grenlan.com
   - Password: {self.admin_password}

STEP 2: Create ForwardAuth Provider
----------------------------------
1. Login: {self.base_url}/if/admin/
2. Go to: Applications → Providers
3. Click: Create
4. Select: Proxy Provider
5. Configure:
   - Name: traefik-forwardauth
   - Authorization flow: default-provider-authorization-explicit-consent
   - Mode: Forward auth (single application)
   - External host: https://auth.homelab.grenlan.com
   - Internal host: http://192.168.1.13:9002
   - Cookie domain: homelab.grenlan.com

STEP 3: Configure Embedded Outpost
---------------------------------
1. Go to: Applications → Outposts
2. Edit: authentik Embedded Outpost
3. Add provider: traefik-forwardauth
4. Save and wait for restart

STEP 4: Create OAuth2 Provider for Grafana
-----------------------------------------
1. Go to: Applications → Providers
2. Click: Create
3. Select: OAuth2/OpenID Provider
4. Configure:
   - Name: grafana-oauth2
   - Authorization flow: default-provider-authorization-explicit-consent
   - Client type: Confidential
   - Client ID: grafana
   - Generate client secret (SAVE THIS!)
   - Redirect URIs: http://192.168.1.12:3000/login/generic_oauth

STEP 5: Create Grafana Application
--------------------------------
1. Go to: Applications → Applications
2. Click: Create
3. Configure:
   - Name: Grafana
   - Slug: grafana
   - Provider: grafana-oauth2
   - Launch URL: http://192.168.1.12:3000

STEP 6: Test Configuration
------------------------
1. ForwardAuth: {self.base_url}/outpost.goauthentik.io/auth/traefik
2. OAuth2 Auth: {self.base_url}/application/o/authorize/
3. OAuth2 Token: {self.base_url}/application/o/token/

Expected ForwardAuth response: HTTP 302 (redirect) or 401 (unauthorized)
"""
        return instructions


def main():
    parser = argparse.ArgumentParser(description='Configure Authentik via API')
    parser.add_argument('--host', default='192.168.1.13:9002', help='Authentik host:port')
    parser.add_argument('--password', default='ChangeMe123!', help='Admin password')
    parser.add_argument('--test-only', action='store_true', help='Only test endpoints')
    
    args = parser.parse_args()
    
    api = AuthentikAPI(args.host, args.password)
    
    if args.test_only:
        # Just test endpoints
        results = api.test_endpoints()
        forwardauth_working = "ForwardAuth" in results and "Working" in results["ForwardAuth"]
        if forwardauth_working:
            print("\n✅ ForwardAuth appears to be configured!")
            return
        else:
            print("\n❌ ForwardAuth not working - configuration needed")
            print(api.generate_instructions())
            return
    
    print("🚀 Starting Authentik configuration...")
    print(f"🎯 Target: {api.base_url}")
    print("="*60)
    
    # Test basic connectivity
    try:
        response = requests.get(f"{api.base_url}/api/v3/root/config/", timeout=5)
        if response.status_code == 200:
            print("✅ Authentik is accessible")
        else:
            print(f"❌ Authentik API error: {response.status_code}")
            sys.exit(1)
    except Exception as e:
        print(f"❌ Cannot connect to Authentik: {e}")
        sys.exit(1)
    
    # Test current endpoint status
    print("\n📊 Current Status:")
    results = api.test_endpoints()
    
    # Check if ForwardAuth is already working
    if "ForwardAuth" in results and "Working" in results["ForwardAuth"]:
        print("\n🎉 ForwardAuth is already configured and working!")
        
        # Check OAuth2 endpoints
        oauth_working = "OAuth2 Authorization" in results and "Working" in results["OAuth2 Authorization"]
        if oauth_working:
            print("🎉 OAuth2 endpoints also appear to be working!")
            print("\n✅ Configuration appears complete!")
        else:
            print("⚠️  OAuth2 endpoints may need configuration")
            print("\nFor Grafana OAuth2 setup, check:")
            print(f"  - {api.base_url}/if/admin/#/core/providers")
            print("  - Look for 'grafana-oauth2' provider")
        
        return
    
    # Generate configuration instructions
    print("\n" + "="*60)
    print("MANUAL CONFIGURATION REQUIRED")
    print("="*60)
    
    instructions = api.generate_instructions()
    print(instructions)
    
    # Save instructions to file
    filename = f"/tmp/authentik-setup-instructions-{int(time.time())}.txt"
    with open(filename, 'w') as f:
        f.write(instructions)
    
    print(f"\n📄 Instructions saved to: {filename}")
    
    # Offer to run periodic checks
    print("\n🔄 Run this script with --test-only to check configuration progress")
    print(f"   python3 {sys.argv[0]} --test-only --host {args.host}")


if __name__ == "__main__":
    main()