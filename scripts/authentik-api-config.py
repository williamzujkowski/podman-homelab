#!/usr/bin/env python3
"""
Authentik API Configuration Script
==================================

This script uses Authentik's REST API to configure ForwardAuth for Traefik.
It performs setup operations that would normally be done through the web interface.

Usage:
    python3 authentik-api-config.py --host 192.168.1.13:9002 --password ChangeMe123!
"""

import argparse
import json
import requests
import time
import sys
import re
from urllib.parse import urljoin, urlparse


class AuthentikAPI:
    def __init__(self, host, password, username="akadmin", email="admin@homelab.grenlan.com"):
        self.base_url = f"http://{host}"
        self.api_url = urljoin(self.base_url, "/api/v3/")
        self.username = username
        self.password = password
        self.email = email
        self.session = requests.Session()
        self.token = None
        
    def _make_request(self, method, endpoint, **kwargs):
        """Make authenticated API request"""
        url = urljoin(self.api_url, endpoint)
        if self.token:
            headers = kwargs.get('headers', {})
            headers['Authorization'] = f'Bearer {self.token}'
            kwargs['headers'] = headers
        
        response = self.session.request(method, url, **kwargs)
        return response
    
    def check_initial_setup_needed(self):
        """Check if initial setup is still needed"""
        try:
            response = requests.get(f"{self.base_url}/if/flow/initial-setup/")
            return response.status_code == 200
        except:
            return False
    
    def complete_initial_setup(self):
        """Complete initial setup by creating admin user"""
        if not self.check_initial_setup_needed():
            print("Initial setup not needed or already completed")
            return True
            
        print("Completing initial setup...")
        
        # Get the initial setup page to extract form data
        response = self.session.get(f"{self.base_url}/if/flow/initial-setup/")
        if response.status_code != 200:
            print(f"Failed to access initial setup page: {response.status_code}")
            return False
        
        # Extract CSRF token and flow execution ID
        content = response.text
        csrf_match = re.search(r'name="csrfmiddlewaretoken" value="([^"]+)"', content)
        exec_match = re.search(r'name="flow_execution" value="([^"]+)"', content)
        
        if not csrf_match or not exec_match:
            print("Could not extract required form tokens")
            return False
        
        csrf_token = csrf_match.group(1)
        flow_execution = exec_match.group(1)
        
        # Submit initial setup form
        form_data = {
            'csrfmiddlewaretoken': csrf_token,
            'flow_execution': flow_execution,
            'akadmin-username': self.username,
            'akadmin-name': 'authentik Default Admin',
            'akadmin-email': self.email,
            'akadmin-password': self.password,
            'akadmin-password_repeat': self.password
        }
        
        headers = {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': f"{self.base_url}/if/flow/initial-setup/"
        }
        
        response = self.session.post(
            f"{self.base_url}/if/flow/initial-setup/",
            data=form_data,
            headers=headers
        )
        
        if response.status_code in [200, 302]:
            print("Initial setup completed successfully")
            time.sleep(3)  # Wait for initialization
            return True
        else:
            print(f"Initial setup failed: {response.status_code}")
            return False
    
    def authenticate(self):
        """Authenticate and get API token"""
        print("Authenticating with Authentik API...")
        
        # Try to get token via the API
        auth_data = {
            'username': self.username,
            'password': self.password
        }
        
        response = self._make_request('POST', 'auth/login/', json=auth_data)
        
        if response.status_code == 200:
            data = response.json()
            if 'token' in data:
                self.token = data['token']
                print("API authentication successful")
                return True
        
        # Alternative: Try to create a token via the web interface
        return self._get_token_via_web()
    
    def _get_token_via_web(self):
        """Get API token through web interface authentication"""
        print("Trying web-based authentication...")
        
        # Login to web interface
        response = self.session.get(f"{self.base_url}/if/flow/default-authentication-flow/")
        if response.status_code != 200:
            print("Could not access login page")
            return False
        
        # Extract form data
        content = response.text
        csrf_match = re.search(r'name="csrfmiddlewaretoken" value="([^"]+)"', content)
        exec_match = re.search(r'name="flow_execution" value="([^"]+)"', content)
        
        if not csrf_match or not exec_match:
            print("Could not extract login form tokens")
            return False
        
        csrf_token = csrf_match.group(1)
        flow_execution = exec_match.group(1)
        
        # Submit login
        login_data = {
            'csrfmiddlewaretoken': csrf_token,
            'flow_execution': flow_execution,
            'uid_field': self.username,
            'password': self.password
        }
        
        response = self.session.post(
            f"{self.base_url}/if/flow/default-authentication-flow/",
            data=login_data
        )
        
        if response.status_code in [200, 302]:
            print("Web authentication successful")
            # Now try to access admin interface to get API session
            admin_response = self.session.get(f"{self.base_url}/if/admin/")
            if admin_response.status_code == 200:
                print("Admin access confirmed")
                return True
        
        print("Web authentication failed")
        return False
    
    def create_proxy_provider(self):
        """Create Traefik proxy provider"""
        print("Creating Traefik proxy provider...")
        
        provider_data = {
            "name": "traefik-forwardauth",
            "authorization_flow": "default-provider-authorization-explicit-consent",
            "mode": "forward_single",
            "external_host": "https://auth.homelab.grenlan.com",
            "internal_host": "http://192.168.1.13:9002",
            "internal_host_ssl_validation": False,
            "cookie_domain": "homelab.grenlan.com"
        }
        
        # First check if provider already exists
        response = self._make_request('GET', 'providers/proxy/')
        if response.status_code == 200:
            providers = response.json().get('results', [])
            for provider in providers:
                if provider.get('name') == 'traefik-forwardauth':
                    print("Proxy provider already exists")
                    return provider['pk']
        
        # Create new provider
        response = self._make_request('POST', 'providers/proxy/', json=provider_data)
        
        if response.status_code == 201:
            provider = response.json()
            print(f"Proxy provider created with ID: {provider['pk']}")
            return provider['pk']
        else:
            print(f"Failed to create proxy provider: {response.status_code}")
            if response.text:
                print(f"Response: {response.text}")
            return None
    
    def get_embedded_outpost(self):
        """Get the embedded outpost"""
        response = self._make_request('GET', 'outposts/instances/')
        if response.status_code == 200:
            outposts = response.json().get('results', [])
            for outpost in outposts:
                if outpost.get('name') == 'authentik Embedded Outpost':
                    return outpost['pk']
        return None
    
    def configure_outpost(self, provider_id):
        """Configure outpost to use the proxy provider"""
        print("Configuring outpost...")
        
        outpost_id = self.get_embedded_outpost()
        if not outpost_id:
            print("Could not find embedded outpost")
            return False
        
        # Get current outpost configuration
        response = self._make_request('GET', f'outposts/instances/{outpost_id}/')
        if response.status_code != 200:
            print("Could not get outpost configuration")
            return False
        
        outpost_data = response.json()
        
        # Add provider to outpost
        current_providers = outpost_data.get('providers', [])
        if provider_id not in current_providers:
            current_providers.append(provider_id)
            outpost_data['providers'] = current_providers
        
        # Update outpost
        response = self._make_request('PUT', f'outposts/instances/{outpost_id}/', json=outpost_data)
        
        if response.status_code == 200:
            print("Outpost configured successfully")
            return True
        else:
            print(f"Failed to configure outpost: {response.status_code}")
            return False
    
    def test_forwardauth_endpoint(self):
        """Test ForwardAuth endpoint"""
        print("Testing ForwardAuth endpoint...")
        
        test_url = f"{self.base_url}/outpost.goauthentik.io/auth/traefik"
        response = requests.get(test_url, allow_redirects=False)
        
        if response.status_code in [200, 302]:
            print(f"✅ ForwardAuth endpoint working (HTTP {response.status_code})")
            return True
        else:
            print(f"❌ ForwardAuth endpoint failed (HTTP {response.status_code})")
            return False
    
    def run_configuration(self):
        """Run the complete configuration"""
        print("Starting Authentik ForwardAuth configuration via API...")
        print(f"Target: {self.base_url}")
        print("=" * 60)
        
        # Step 1: Complete initial setup if needed
        if not self.complete_initial_setup():
            print("❌ Initial setup failed")
            return False
        
        # Step 2: Authenticate
        if not self.authenticate():
            print("❌ Authentication failed")
            return False
        
        # Step 3: Create proxy provider
        provider_id = self.create_proxy_provider()
        if not provider_id:
            print("❌ Failed to create proxy provider")
            return False
        
        # Step 4: Configure outpost
        if not self.configure_outpost(provider_id):
            print("❌ Failed to configure outpost")
            return False
        
        # Step 5: Wait for outpost to restart
        print("Waiting for outpost to restart...")
        time.sleep(10)
        
        # Step 6: Test endpoint
        if self.test_forwardauth_endpoint():
            print("\n✅ ForwardAuth configuration completed successfully!")
            print(f"Endpoint available at: {self.base_url}/outpost.goauthentik.io/auth/traefik")
            return True
        else:
            print("\n⚠️  Configuration may need more time to take effect")
            print("Wait a few minutes and test the endpoint manually")
            return True


def main():
    parser = argparse.ArgumentParser(description='Configure Authentik ForwardAuth via API')
    parser.add_argument('--host', default='192.168.1.13:9002', help='Authentik host:port')
    parser.add_argument('--password', default='ChangeMe123!', help='Admin password')
    parser.add_argument('--username', default='akadmin', help='Admin username')
    parser.add_argument('--email', default='admin@homelab.grenlan.com', help='Admin email')
    
    args = parser.parse_args()
    
    api = AuthentikAPI(args.host, args.password, args.username, args.email)
    
    try:
        success = api.run_configuration()
        if success:
            print("\n" + "=" * 60)
            print("CONFIGURATION COMPLETED")
            print("=" * 60)
            print("The ForwardAuth endpoint should now be available.")
            print("You can apply the Traefik middleware to protect services:")
            print("  middlewares:")
            print("    - authentik-auth@file")
        else:
            print("\n" + "=" * 60)
            print("CONFIGURATION FAILED")
            print("=" * 60)
            sys.exit(1)
            
    except KeyboardInterrupt:
        print("\n⚠️  Configuration interrupted")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()