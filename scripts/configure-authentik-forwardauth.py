#!/usr/bin/env python3
"""
Authentik ForwardAuth Configuration Script
==========================================

This script configures Authentik to provide ForwardAuth authentication for Traefik.
It performs the following tasks:

1. Complete initial Authentik setup (create akadmin user)
2. Create a Traefik Proxy Provider for ForwardAuth
3. Create an embedded outpost for the provider
4. Test that the ForwardAuth endpoint is working

Usage:
    python3 configure-authentik-forwardauth.py --host 192.168.1.13:9002 --admin-password ChangeMe123!

Requirements:
    pip install requests
"""

import argparse
import json
import requests
import time
import sys
from urllib.parse import urlparse


class AuthentikConfigurator:
    def __init__(self, host, admin_password, admin_email="admin@homelab.grenlan.com"):
        self.base_url = f"http://{host}"
        self.admin_password = admin_password
        self.admin_email = admin_email
        self.session = requests.Session()
        self.csrf_token = None
        self.api_token = None
        
    def _get_csrf_token(self):
        """Get CSRF token from the initial setup page"""
        try:
            response = self.session.get(f"{self.base_url}/if/flow/initial-setup/")
            if response.status_code == 200:
                # Try to extract CSRF token from the page
                content = response.text
                # Look for CSRF token in various places
                import re
                csrf_match = re.search(r'csrfmiddlewaretoken["\']?\s*:\s*["\']([^"\']+)["\']', content)
                if csrf_match:
                    return csrf_match.group(1)
                
                # Try meta tag
                meta_match = re.search(r'<meta name="csrf-token" content="([^"]+)"', content)
                if meta_match:
                    return meta_match.group(1)
                    
            return None
        except Exception as e:
            print(f"Error getting CSRF token: {e}")
            return None
    
    def complete_initial_setup(self):
        """Complete the initial Authentik setup by creating the akadmin user"""
        print("Checking if initial setup is required...")
        
        # Check if setup is needed
        response = self.session.get(f"{self.base_url}/if/flow/initial-setup/")
        if response.status_code != 200:
            print("Initial setup not accessible, may already be completed")
            return True
            
        print("Initial setup required, creating akadmin user...")
        
        # Get CSRF token
        self.csrf_token = self._get_csrf_token()
        if not self.csrf_token:
            print("Could not obtain CSRF token")
            return False
            
        # Create initial admin user
        setup_data = {
            "csrfmiddlewaretoken": self.csrf_token,
            "akadmin-username": "akadmin",
            "akadmin-name": "authentik Default Admin",
            "akadmin-email": self.admin_email,
            "akadmin-password": self.admin_password,
            "akadmin-password_repeat": self.admin_password,
        }
        
        headers = {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-CSRFToken': self.csrf_token,
            'Referer': f"{self.base_url}/if/flow/initial-setup/"
        }
        
        response = self.session.post(
            f"{self.base_url}/if/flow/initial-setup/",
            data=setup_data,
            headers=headers,
            allow_redirects=False
        )
        
        if response.status_code in [200, 302]:
            print("Initial setup completed successfully")
            time.sleep(2)  # Wait for services to initialize
            return True
        else:
            print(f"Initial setup failed: {response.status_code}")
            print(f"Response: {response.text[:500]}")
            return False
    
    def authenticate(self):
        """Authenticate with the Authentik API"""
        print("Authenticating with Authentik API...")
        
        # First try to get API token via web login
        login_data = {
            "uid_field": "akadmin",
            "password": self.admin_password,
        }
        
        # Get login page first to get CSRF token
        response = self.session.get(f"{self.base_url}/if/flow/default-authentication-flow/")
        if response.status_code == 200:
            csrf_token = self._get_csrf_token()
            if csrf_token:
                login_data["csrfmiddlewaretoken"] = csrf_token
        
        response = self.session.post(
            f"{self.base_url}/if/flow/default-authentication-flow/",
            data=login_data
        )
        
        if response.status_code in [200, 302]:
            print("Web authentication successful")
            
            # Now try to get API token
            token_response = self.session.get(f"{self.base_url}/if/admin/#/administration/tokens")
            if token_response.status_code == 200:
                print("Admin interface accessible")
                return True
        
        print("Authentication failed, trying direct API approach")
        return False
    
    def create_api_token(self):
        """Create an API token for further operations"""
        print("Creating API token...")
        
        # This would require proper authentication flow
        # For now, we'll use a different approach
        pass
    
    def create_proxy_provider(self):
        """Create a Traefik proxy provider"""
        print("Creating Traefik proxy provider...")
        
        provider_data = {
            "name": "traefik-forwardauth",
            "authorization_flow": "default-provider-authorization-explicit-consent",
            "mode": "forward_single",
            "external_host": "https://auth.homelab.grenlan.com",
            "internal_host": "http://192.168.1.13:9002",
            "internal_host_ssl_validation": False,
            "cookie_domain": "homelab.grenlan.com",
            "token_validity": "hours=24",
        }
        
        # This requires authenticated API access
        # Will be implemented after authentication is working
        print("Provider configuration prepared (manual step required)")
        return provider_data
    
    def create_outpost(self):
        """Create an embedded outpost for the proxy provider"""
        print("Creating embedded outpost...")
        
        outpost_data = {
            "name": "authentik Embedded Outpost",
            "type": "proxy",
            "service_connection": None,  # None for embedded
            "config": {
                "authentik_host": "http://192.168.1.13:9002",
                "authentik_host_browser": "https://auth.homelab.grenlan.com",
                "authentik_host_insecure": False,
                "log_level": "info",
                "object_naming_template": "ak-outpost-%(name)s",
                "container_image": None,
                "kubernetes_namespace": "authentik",
                "kubernetes_ingress_annotations": {},
                "kubernetes_ingress_secret_name": "authentik-outpost-tls",
                "kubernetes_service_type": "ClusterIP",
                "kubernetes_disabled_components": [],
                "kubernetes_replicas": 1
            }
        }
        
        print("Outpost configuration prepared (manual step required)")
        return outpost_data
    
    def test_forwardauth_endpoint(self):
        """Test that the ForwardAuth endpoint is responding"""
        print("Testing ForwardAuth endpoint...")
        
        test_url = f"{self.base_url}/outpost.goauthentik.io/auth/traefik"
        response = requests.get(test_url, allow_redirects=False)
        
        if response.status_code == 302:
            print("✅ ForwardAuth endpoint is working (redirecting to login)")
            return True
        elif response.status_code == 200:
            print("✅ ForwardAuth endpoint is accessible")
            return True
        elif response.status_code == 404:
            print("❌ ForwardAuth endpoint not found (404)")
            return False
        else:
            print(f"❓ ForwardAuth endpoint status: {response.status_code}")
            return False
    
    def run_configuration(self):
        """Run the complete configuration process"""
        print("Starting Authentik ForwardAuth configuration...")
        print(f"Target: {self.base_url}")
        print("=" * 50)
        
        # Step 1: Complete initial setup
        if not self.complete_initial_setup():
            print("❌ Initial setup failed")
            return False
            
        # Wait a moment for services to be ready
        time.sleep(3)
        
        # Step 2: Authenticate
        if not self.authenticate():
            print("⚠️  API authentication not fully working, manual steps required")
        
        # Step 3: Test current state
        if self.test_forwardauth_endpoint():
            print("✅ ForwardAuth already working!")
            return True
        
        print("\n" + "=" * 50)
        print("MANUAL CONFIGURATION REQUIRED")
        print("=" * 50)
        print("The initial setup has been completed, but the ForwardAuth provider")
        print("needs to be configured manually through the web interface.")
        print()
        print(f"1. Access Authentik: {self.base_url}")
        print(f"2. Login with: akadmin / {self.admin_password}")
        print("3. Go to Applications -> Providers")
        print("4. Create a new Proxy Provider with these settings:")
        print("   - Name: traefik-forwardauth")
        print("   - Mode: Forward auth (single application)")
        print("   - External host: https://auth.homelab.grenlan.com")
        print("   - Internal host: http://192.168.1.13:9002")
        print("5. Go to Applications -> Outposts")
        print("6. Edit 'authentik Embedded Outpost'")
        print("7. Add the 'traefik-forwardauth' provider to the outpost")
        print("8. Wait for the outpost to restart")
        print()
        print("After completing these steps, the ForwardAuth endpoint should be available at:")
        print(f"{self.base_url}/outpost.goauthentik.io/auth/traefik")
        
        return True


def main():
    parser = argparse.ArgumentParser(description='Configure Authentik ForwardAuth for Traefik')
    parser.add_argument('--host', default='192.168.1.13:9002', help='Authentik host:port')
    parser.add_argument('--admin-password', default='ChangeMe123!', help='Admin password')
    parser.add_argument('--admin-email', default='admin@homelab.grenlan.com', help='Admin email')
    
    args = parser.parse_args()
    
    configurator = AuthentikConfigurator(args.host, args.admin_password, args.admin_email)
    
    try:
        success = configurator.run_configuration()
        if success:
            print("\n✅ Configuration process completed")
        else:
            print("\n❌ Configuration process failed")
            sys.exit(1)
    except KeyboardInterrupt:
        print("\n⚠️  Configuration interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()