#!/usr/bin/env python3
"""
Authentik Manual Setup Script with Browser Automation
====================================================

This script uses Playwright to automate the browser setup of Authentik ForwardAuth.
It performs:
1. Complete initial setup if needed
2. Create Proxy Provider for ForwardAuth  
3. Configure Embedded Outpost
4. Create OAuth2 Provider for Grafana
"""

import asyncio
import sys
import argparse
from playwright.async_api import async_playwright


class AuthentikSetup:
    def __init__(self, host, admin_password, headless=True):
        self.host = host
        self.base_url = f"http://{host}"
        self.admin_password = admin_password
        self.headless = headless
        
    async def setup_authentik(self):
        """Main setup process"""
        async with async_playwright() as p:
            # Launch browser
            browser = await p.chromium.launch(headless=self.headless)
            page = await browser.new_page()
            
            try:
                # Step 1: Complete initial setup if needed
                print("Step 1: Checking initial setup...")
                await page.goto(f"{self.base_url}/if/flow/initial-setup/")
                await page.wait_for_load_state('networkidle')
                
                # Check if we're redirected or if setup is needed
                current_url = page.url
                if "initial-setup" in current_url:
                    print("Initial setup required, creating admin user...")
                    await self._complete_initial_setup(page)
                else:
                    print("Initial setup already completed")
                
                # Step 2: Login to admin interface
                print("\nStep 2: Logging in to admin interface...")
                await self._login_admin(page)
                
                # Step 3: Create Proxy Provider for ForwardAuth
                print("\nStep 3: Creating Proxy Provider for ForwardAuth...")
                await self._create_proxy_provider(page)
                
                # Step 4: Configure Embedded Outpost
                print("\nStep 4: Configuring Embedded Outpost...")
                await self._configure_outpost(page)
                
                # Step 5: Create OAuth2 Provider for Grafana
                print("\nStep 5: Creating OAuth2 Provider for Grafana...")
                await self._create_oauth2_provider(page)
                
                print("\n✅ Authentik setup completed successfully!")
                
            except Exception as e:
                print(f"❌ Setup failed: {e}")
                # Take screenshot on error
                await page.screenshot(path="/tmp/authentik-setup-error.png")
                print("Screenshot saved to /tmp/authentik-setup-error.png")
                raise
            finally:
                await browser.close()
    
    async def _complete_initial_setup(self, page):
        """Complete the initial setup by creating admin user"""
        try:
            # Wait for the form to load
            await page.wait_for_selector('input[name*="username"]', timeout=10000)
            
            # Fill out the initial setup form
            await page.fill('input[name*="username"]', 'akadmin')
            await page.fill('input[name*="name"]', 'authentik Default Admin')  
            await page.fill('input[name*="email"]', 'admin@homelab.grenlan.com')
            await page.fill('input[name*="password"]', self.admin_password)
            await page.fill('input[name*="password_repeat"]', self.admin_password)
            
            # Submit the form
            await page.click('button[type="submit"]')
            
            # Wait for completion
            await page.wait_for_load_state('networkidle')
            print("✅ Initial setup completed")
            
        except Exception as e:
            print(f"Initial setup failed: {e}")
            raise
    
    async def _login_admin(self, page):
        """Login to admin interface"""
        try:
            # Navigate to admin interface
            await page.goto(f"{self.base_url}/if/admin/")
            await page.wait_for_load_state('networkidle')
            
            # Check if already logged in
            if "/if/admin/" in page.url and "login" not in page.url:
                print("✅ Already logged in to admin interface")
                return
            
            # Fill login form
            await page.wait_for_selector('input[name*="uid_field"]', timeout=10000)
            await page.fill('input[name*="uid_field"]', 'akadmin')
            await page.fill('input[name*="password"]', self.admin_password)
            
            # Submit login
            await page.click('button[type="submit"]')
            await page.wait_for_load_state('networkidle')
            
            print("✅ Logged in to admin interface")
            
        except Exception as e:
            print(f"Admin login failed: {e}")
            raise
    
    async def _create_proxy_provider(self, page):
        """Create Proxy Provider for ForwardAuth"""
        try:
            # Navigate to Providers
            await page.goto(f"{self.base_url}/if/admin/#/core/providers")
            await page.wait_for_load_state('networkidle')
            
            # Check if provider already exists
            existing_provider = await page.query_selector('text=traefik-forwardauth')
            if existing_provider:
                print("✅ ForwardAuth provider already exists")
                return
            
            # Create new provider
            await page.click('text=Create')
            await page.wait_for_selector('text=Proxy Provider')
            await page.click('text=Proxy Provider')
            
            # Fill provider form
            await page.fill('input[name="name"]', 'traefik-forwardauth')
            
            # Select authorization flow
            await page.click('select[name="authorization_flow"]')
            await page.select_option('select[name="authorization_flow"]', 'default-provider-authorization-explicit-consent')
            
            # Set mode to Forward auth (single application)
            await page.click('select[name="mode"]')
            await page.select_option('select[name="mode"]', 'forward_single')
            
            # Set external host
            await page.fill('input[name="external_host"]', 'https://auth.homelab.grenlan.com')
            
            # Set internal host  
            await page.fill('input[name="internal_host"]', 'http://192.168.1.13:9002')
            
            # Set cookie domain
            await page.fill('input[name="cookie_domain"]', 'homelab.grenlan.com')
            
            # Submit form
            await page.click('button[type="submit"]')
            await page.wait_for_load_state('networkidle')
            
            print("✅ ForwardAuth provider created")
            
        except Exception as e:
            print(f"Provider creation failed: {e}")
            raise
    
    async def _configure_outpost(self, page):
        """Configure Embedded Outpost"""
        try:
            # Navigate to Outposts
            await page.goto(f"{self.base_url}/if/admin/#/outpost/outposts")
            await page.wait_for_load_state('networkidle')
            
            # Find and edit embedded outpost
            await page.click('text=authentik Embedded Outpost')
            await page.wait_for_load_state('networkidle')
            
            # Check if provider is already added
            forwardauth_selected = await page.query_selector('text=traefik-forwardauth')
            if forwardauth_selected:
                print("✅ ForwardAuth provider already added to outpost")
                return
            
            # Add the ForwardAuth provider to the outpost
            await page.click('text=traefik-forwardauth')
            
            # Save changes
            await page.click('button[type="submit"]')
            await page.wait_for_load_state('networkidle')
            
            print("✅ Outpost configured with ForwardAuth provider")
            
            # Wait for outpost to restart
            print("Waiting for outpost to restart...")
            await asyncio.sleep(10)
            
        except Exception as e:
            print(f"Outpost configuration failed: {e}")
            raise
    
    async def _create_oauth2_provider(self, page):
        """Create OAuth2 Provider for Grafana"""
        try:
            # Navigate to Providers
            await page.goto(f"{self.base_url}/if/admin/#/core/providers")
            await page.wait_for_load_state('networkidle')
            
            # Check if Grafana OAuth2 provider already exists
            existing_grafana = await page.query_selector('text=grafana-oauth2')
            if existing_grafana:
                print("✅ Grafana OAuth2 provider already exists")
                return
            
            # Create new provider
            await page.click('text=Create')
            await page.wait_for_selector('text=OAuth2/OpenID Provider')
            await page.click('text=OAuth2/OpenID Provider')
            
            # Fill OAuth2 provider form
            await page.fill('input[name="name"]', 'grafana-oauth2')
            
            # Set authorization flow
            await page.click('select[name="authorization_flow"]')
            await page.select_option('select[name="authorization_flow"]', 'default-provider-authorization-explicit-consent')
            
            # Set client type to Confidential
            await page.click('select[name="client_type"]')
            await page.select_option('select[name="client_type"]', 'confidential')
            
            # Set client ID
            await page.fill('input[name="client_id"]', 'grafana')
            
            # Generate client secret (will be shown after creation)
            await page.click('button:has-text("Generate")')
            
            # Set redirect URIs
            await page.fill('textarea[name="redirect_uris"]', 'http://192.168.1.12:3000/login/generic_oauth')
            
            # Submit form
            await page.click('button[type="submit"]')
            await page.wait_for_load_state('networkidle')
            
            print("✅ OAuth2 provider for Grafana created")
            
            # Try to get the client secret
            client_secret_elem = await page.query_selector('.pf-c-clipboard-copy__text')
            if client_secret_elem:
                client_secret = await client_secret_elem.inner_text()
                print(f"📝 Grafana OAuth2 Client Secret: {client_secret}")
                
                # Save to file for later use
                with open('/tmp/grafana-oauth2-secret.txt', 'w') as f:
                    f.write(f"CLIENT_ID=grafana\n")
                    f.write(f"CLIENT_SECRET={client_secret}\n")
                print("📁 Credentials saved to /tmp/grafana-oauth2-secret.txt")
            
        except Exception as e:
            print(f"OAuth2 provider creation failed: {e}")
            # Continue anyway as ForwardAuth is the primary goal


async def main():
    parser = argparse.ArgumentParser(description='Setup Authentik with browser automation')
    parser.add_argument('--host', default='192.168.1.13:9002', help='Authentik host:port')
    parser.add_argument('--admin-password', default='ChangeMe123!', help='Admin password')
    parser.add_argument('--headless', action='store_true', help='Run browser in headless mode')
    
    args = parser.parse_args()
    
    setup = AuthentikSetup(args.host, args.admin_password, args.headless)
    
    try:
        await setup.setup_authentik()
        print("\n🎉 All setup tasks completed!")
    except Exception as e:
        print(f"\n💥 Setup failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())