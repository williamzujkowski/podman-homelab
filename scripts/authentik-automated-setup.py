#!/usr/bin/env python3
"""
Authentik Automated Setup with Playwright
==========================================
This script uses Playwright to automate Authentik configuration
"""

import asyncio
import sys
import argparse
import json
import time
from playwright.async_api import async_playwright


class AuthentikAutomation:
    def __init__(self, host, admin_password, headless=True):
        self.host = host
        self.base_url = f"http://{host}"
        self.admin_password = admin_password
        self.headless = headless
        self.oauth_client_secret = None
        
    async def run_setup(self):
        """Main automation routine"""
        async with async_playwright() as p:
            # Launch browser
            browser = await p.chromium.launch(
                headless=self.headless,
                args=['--no-sandbox', '--disable-dev-shm-usage']
            )
            
            context = await browser.new_context()
            page = await context.new_page()
            
            # Set longer timeout for page operations
            page.set_default_timeout(30000)
            
            try:
                print("🚀 Starting Authentik automated setup...")
                print(f"🎯 Target: {self.base_url}")
                
                # Step 1: Handle initial setup if needed
                await self._handle_initial_setup(page)
                
                # Step 2: Login to admin interface
                await self._login_admin(page)
                
                # Step 3: Create ForwardAuth provider
                await self._create_forwardauth_provider(page)
                
                # Step 4: Configure outpost
                await self._configure_outpost(page)
                
                # Step 5: Create OAuth2 provider for Grafana
                await self._create_oauth2_provider(page)
                
                print("\n🎉 Setup completed successfully!")
                
                # Save configuration details
                await self._save_configuration()
                
            except Exception as e:
                print(f"❌ Setup failed: {e}")
                # Take screenshot on error
                screenshot_path = f"/tmp/authentik-error-{int(time.time())}.png"
                await page.screenshot(path=screenshot_path)
                print(f"📸 Error screenshot saved: {screenshot_path}")
                raise
                
            finally:
                await browser.close()
                
    async def _handle_initial_setup(self, page):
        """Handle initial setup if needed"""
        print("\n📋 Step 1: Checking initial setup...")
        
        try:
            await page.goto(f"{self.base_url}/if/flow/initial-setup/", wait_until='networkidle')
            
            # Wait a moment for JavaScript to load
            await asyncio.sleep(2)
            
            # Check if we're on the setup page or already past it
            title = await page.title()
            current_url = page.url
            
            print(f"   Current URL: {current_url}")
            print(f"   Page title: {title}")
            
            # Look for setup form elements
            username_input = await page.query_selector('input[name*="username"], input[placeholder*="username"]')
            if username_input:
                print("   Initial setup form found, filling out...")
                
                # Fill the setup form
                await page.fill('input[name*="username"], input[placeholder*="username"]', 'akadmin')
                
                # Try different possible field names for other inputs
                await page.fill('input[name*="name"], input[placeholder*="name"]', 'authentik Default Admin')
                await page.fill('input[name*="email"], input[placeholder*="email"]', 'admin@homelab.grenlan.com')
                
                password_fields = await page.query_selector_all('input[type="password"]')
                for field in password_fields:
                    await field.fill(self.admin_password)
                
                # Submit the form
                submit_button = await page.query_selector('button[type="submit"], button:has-text("Create"), button:has-text("Continue")')
                if submit_button:
                    await submit_button.click()
                    await page.wait_for_load_state('networkidle')
                    print("   ✅ Initial setup completed")
                else:
                    print("   ⚠️  Could not find submit button")
            else:
                print("   ✅ Initial setup already completed")
                
        except Exception as e:
            print(f"   ⚠️  Initial setup handling failed: {e}")
            # Continue anyway - setup might already be done
    
    async def _login_admin(self, page):
        """Login to admin interface"""
        print("\n🔐 Step 2: Logging into admin interface...")
        
        try:
            await page.goto(f"{self.base_url}/if/admin/", wait_until='networkidle')
            await asyncio.sleep(2)
            
            current_url = page.url
            print(f"   Current URL: {current_url}")
            
            # Check if already logged in (URL doesn't contain login flow)
            if "/if/admin/" in current_url and "/flow/" not in current_url:
                print("   ✅ Already logged in to admin interface")
                return
                
            # Look for login form
            username_field = await page.query_selector('input[name*="uid"], input[placeholder*="username"], input[type="text"]')
            password_field = await page.query_selector('input[name*="password"], input[type="password"]')
            
            if username_field and password_field:
                print("   Filling login form...")
                await username_field.fill('akadmin')
                await password_field.fill(self.admin_password)
                
                # Submit login
                login_button = await page.query_selector('button[type="submit"], button:has-text("Sign in"), button:has-text("Login")')
                if login_button:
                    await login_button.click()
                    await page.wait_for_load_state('networkidle')
                    await asyncio.sleep(2)
                    print("   ✅ Logged in successfully")
                else:
                    print("   ⚠️  Could not find login button")
            else:
                print("   ⚠️  Could not find login form")
                
        except Exception as e:
            print(f"   ❌ Login failed: {e}")
            raise
    
    async def _create_forwardauth_provider(self, page):
        """Create ForwardAuth proxy provider"""
        print("\n🔗 Step 3: Creating ForwardAuth provider...")
        
        try:
            # Navigate to providers
            await page.goto(f"{self.base_url}/if/admin/#/core/providers", wait_until='networkidle')
            await asyncio.sleep(3)
            
            # Check if provider already exists
            existing = await page.query_selector('text=traefik-forwardauth')
            if existing:
                print("   ✅ ForwardAuth provider already exists")
                return
                
            # Create new provider
            create_button = await page.query_selector('button:has-text("Create"), ak-wizard-main button')
            if create_button:
                await create_button.click()
                await asyncio.sleep(2)
                
                # Select Proxy Provider
                proxy_option = await page.query_selector('text="Proxy Provider"')
                if proxy_option:
                    await proxy_option.click()
                    await asyncio.sleep(1)
                    
                    # Continue/Next button
                    next_button = await page.query_selector('button:has-text("Continue"), button:has-text("Next")')
                    if next_button:
                        await next_button.click()
                        await asyncio.sleep(2)
                        
                        # Fill provider details
                        await page.fill('input[name="name"]', 'traefik-forwardauth')
                        
                        # Select mode - try different selectors
                        mode_select = await page.query_selector('select[name="mode"]')
                        if mode_select:
                            await page.select_option('select[name="mode"]', 'forward_single')
                        
                        # Fill hosts
                        ext_host = await page.query_selector('input[name="external_host"]')
                        if ext_host:
                            await ext_host.fill('https://auth.homelab.grenlan.com')
                            
                        int_host = await page.query_selector('input[name="internal_host"]')  
                        if int_host:
                            await int_host.fill('http://192.168.1.13:9002')
                            
                        # Cookie domain
                        cookie_field = await page.query_selector('input[name="cookie_domain"]')
                        if cookie_field:
                            await cookie_field.fill('homelab.grenlan.com')
                        
                        # Submit/Create
                        create_final = await page.query_selector('button[type="submit"], button:has-text("Create")')
                        if create_final:
                            await create_final.click()
                            await page.wait_for_load_state('networkidle')
                            print("   ✅ ForwardAuth provider created")
                        else:
                            print("   ⚠️  Could not find create button")
                    else:
                        print("   ⚠️  Could not find next button")
                else:
                    print("   ⚠️  Could not find Proxy Provider option")
            else:
                print("   ⚠️  Could not find create button")
                
        except Exception as e:
            print(f"   ❌ Provider creation failed: {e}")
            # Continue with next steps
    
    async def _configure_outpost(self, page):
        """Configure embedded outpost"""
        print("\n⚡ Step 4: Configuring embedded outpost...")
        
        try:
            # Navigate to outposts
            await page.goto(f"{self.base_url}/if/admin/#/outpost/outposts", wait_until='networkidle')
            await asyncio.sleep(3)
            
            # Look for embedded outpost
            embedded_outpost = await page.query_selector('text="authentik Embedded Outpost"')
            if embedded_outpost:
                await embedded_outpost.click()
                await asyncio.sleep(2)
                
                # Look for provider selection area
                # This is complex in the UI, so we'll use a simpler approach
                # Look for the forwardauth provider and try to select it
                forwardauth_checkbox = await page.query_selector('text=traefik-forwardauth')
                if forwardauth_checkbox:
                    await forwardauth_checkbox.click()
                    await asyncio.sleep(1)
                    
                    # Save/Update
                    update_button = await page.query_selector('button:has-text("Update"), button[type="submit"]')
                    if update_button:
                        await update_button.click()
                        await page.wait_for_load_state('networkidle')
                        print("   ✅ Outpost configured")
                        
                        # Wait for restart
                        print("   ⏱️  Waiting for outpost to restart...")
                        await asyncio.sleep(10)
                    else:
                        print("   ⚠️  Could not find update button")
                else:
                    print("   ⚠️  Could not find ForwardAuth provider to add")
            else:
                print("   ⚠️  Could not find embedded outpost")
                
        except Exception as e:
            print(f"   ❌ Outpost configuration failed: {e}")
    
    async def _create_oauth2_provider(self, page):
        """Create OAuth2 provider for Grafana"""
        print("\n🔐 Step 5: Creating OAuth2 provider for Grafana...")
        
        try:
            # Navigate back to providers
            await page.goto(f"{self.base_url}/if/admin/#/core/providers", wait_until='networkidle')
            await asyncio.sleep(3)
            
            # Check if Grafana provider already exists
            existing_grafana = await page.query_selector('text=grafana-oauth2')
            if existing_grafana:
                print("   ✅ Grafana OAuth2 provider already exists")
                return
                
            # Create new provider
            create_button = await page.query_selector('button:has-text("Create")')
            if create_button:
                await create_button.click()
                await asyncio.sleep(2)
                
                # Select OAuth2/OpenID Provider
                oauth_option = await page.query_selector('text="OAuth2/OpenID Provider"')
                if oauth_option:
                    await oauth_option.click()
                    await asyncio.sleep(1)
                    
                    # Continue
                    next_button = await page.query_selector('button:has-text("Continue"), button:has-text("Next")')
                    if next_button:
                        await next_button.click()
                        await asyncio.sleep(2)
                        
                        # Fill OAuth2 details
                        await page.fill('input[name="name"]', 'grafana-oauth2')
                        await page.fill('input[name="client_id"]', 'grafana')
                        
                        # Client type to confidential
                        client_type_select = await page.query_selector('select[name="client_type"]')
                        if client_type_select:
                            await page.select_option('select[name="client_type"]', 'confidential')
                        
                        # Redirect URIs
                        redirect_field = await page.query_selector('textarea[name="redirect_uris"], input[name="redirect_uris"]')
                        if redirect_field:
                            await redirect_field.fill('http://192.168.1.12:3000/login/generic_oauth')
                        
                        # Submit
                        create_final = await page.query_selector('button[type="submit"], button:has-text("Create")')
                        if create_final:
                            await create_final.click()
                            await page.wait_for_load_state('networkidle')
                            await asyncio.sleep(2)
                            
                            # Try to get the client secret
                            secret_element = await page.query_selector('.pf-c-clipboard-copy__text, code')
                            if secret_element:
                                self.oauth_client_secret = await secret_element.inner_text()
                                print(f"   ✅ OAuth2 provider created")
                                print(f"   🔑 Client Secret: {self.oauth_client_secret}")
                            else:
                                print("   ✅ OAuth2 provider created (secret not captured)")
                        else:
                            print("   ⚠️  Could not find create button")
                    else:
                        print("   ⚠️  Could not find next button")
                else:
                    print("   ⚠️  Could not find OAuth2 Provider option")
            else:
                print("   ⚠️  Could not find create button")
                
        except Exception as e:
            print(f"   ❌ OAuth2 provider creation failed: {e}")
    
    async def _save_configuration(self):
        """Save configuration details"""
        config = {
            "timestamp": int(time.time()),
            "base_url": self.base_url,
            "admin_user": "akadmin",
            "forwardauth_provider": "traefik-forwardauth",
            "oauth2_provider": "grafana-oauth2",
            "oauth2_client_id": "grafana",
            "oauth2_client_secret": self.oauth_client_secret,
            "oauth2_redirect_uri": "http://192.168.1.12:3000/login/generic_oauth",
            "endpoints": {
                "forwardauth": f"{self.base_url}/outpost.goauthentik.io/auth/traefik",
                "oauth2_auth": f"{self.base_url}/application/o/authorize/",
                "oauth2_token": f"{self.base_url}/application/o/token/",
                "oauth2_userinfo": f"{self.base_url}/application/o/userinfo/"
            }
        }
        
        config_file = f"/tmp/authentik-config-{config['timestamp']}.json"
        with open(config_file, 'w') as f:
            json.dump(config, indent=2, fp=f)
        
        print(f"\n📄 Configuration saved to: {config_file}")
        
        if self.oauth_client_secret:
            # Also save as env file for easy use
            env_file = f"/tmp/grafana-oauth2-credentials.env"
            with open(env_file, 'w') as f:
                f.write(f"GRAFANA_OAUTH2_CLIENT_ID=grafana\n")
                f.write(f"GRAFANA_OAUTH2_CLIENT_SECRET={self.oauth_client_secret}\n")
            print(f"📄 Grafana credentials saved to: {env_file}")


async def main():
    parser = argparse.ArgumentParser(description='Automated Authentik setup')
    parser.add_argument('--host', default='192.168.1.13:9002', help='Authentik host:port')
    parser.add_argument('--password', default='ChangeMe123!', help='Admin password')
    parser.add_argument('--headed', action='store_true', help='Run browser in headed mode (visible)')
    
    args = parser.parse_args()
    
    automation = AuthentikAutomation(args.host, args.password, headless=not args.headed)
    
    try:
        await automation.run_setup()
        
        print("\n" + "="*60)
        print("🎊 SETUP COMPLETED!")
        print("="*60)
        print("Next steps:")
        print("1. Test ForwardAuth endpoint")
        print("2. Configure Grafana OAuth2")
        print("3. Test complete authentication flow")
        
    except Exception as e:
        print(f"\n💥 Setup failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())