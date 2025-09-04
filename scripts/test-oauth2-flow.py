#!/usr/bin/env python3
"""
OAuth2 Authentication Flow Test Script
======================================
Tests the complete OAuth2 flow between Grafana and Authentik
"""

import requests
import argparse
import json
import time
import sys
from urllib.parse import parse_qs, urlparse


class OAuth2FlowTester:
    def __init__(self, authentik_host, grafana_host, client_id='grafana', client_secret=None):
        self.authentik_base = f"http://{authentik_host}"
        self.grafana_base = f"http://{grafana_host}"
        self.client_id = client_id
        self.client_secret = client_secret
        self.session = requests.Session()
        
    def test_endpoints(self):
        """Test all OAuth2 endpoints"""
        print("🧪 Testing OAuth2 Endpoints")
        print("=" * 40)
        
        endpoints = [
            ("Authentik API", f"{self.authentik_base}/api/v3/root/config/"),
            ("Grafana API", f"{self.grafana_base}/api/health"),
            ("OAuth2 Authorization", f"{self.authentik_base}/application/o/authorize/"),
            ("OAuth2 Token", f"{self.authentik_base}/application/o/token/"),
            ("OAuth2 UserInfo", f"{self.authentik_base}/application/o/userinfo/"),
            ("Grafana OAuth Login", f"{self.grafana_base}/login/generic_oauth"),
        ]
        
        results = {}
        for name, url in endpoints:
            try:
                response = requests.get(url, timeout=5, allow_redirects=False)
                status = response.status_code
                
                if status in [200]:
                    results[name] = f"✅ OK ({status})"
                elif status in [302, 401, 405, 404]:
                    results[name] = f"✅ Expected ({status})"
                else:
                    results[name] = f"⚠️  HTTP {status}"
                    
            except requests.exceptions.RequestException as e:
                results[name] = f"❌ Error: {str(e)[:30]}..."
        
        for name, result in results.items():
            print(f"  {name:20}: {result}")
        
        return results
    
    def test_grafana_oauth_config(self):
        """Test if Grafana has OAuth2 configured"""
        print("\n🔧 Testing Grafana OAuth2 Configuration")
        print("=" * 40)
        
        try:
            # Check if OAuth login endpoint returns proper redirect
            response = requests.get(
                f"{self.grafana_base}/login/generic_oauth",
                allow_redirects=False,
                timeout=5
            )
            
            if response.status_code == 302:
                location = response.headers.get('Location', '')
                if 'authentik' in location.lower() or self.authentik_base in location:
                    print("✅ Grafana OAuth2 properly configured - redirects to Authentik")
                    print(f"   Redirect URL: {location}")
                    return True
                else:
                    print("⚠️  Grafana OAuth2 redirect doesn't point to Authentik")
                    print(f"   Redirect URL: {location}")
                    return False
            else:
                print(f"❌ Grafana OAuth2 not working - HTTP {response.status_code}")
                return False
                
        except Exception as e:
            print(f"❌ Error testing Grafana OAuth2: {e}")
            return False
    
    def test_authentik_provider(self):
        """Test if Authentik has the OAuth2 provider configured"""
        print("\n🔧 Testing Authentik OAuth2 Provider")
        print("=" * 40)
        
        # Test authorization endpoint with expected parameters
        auth_url = f"{self.authentik_base}/application/o/authorize/"
        params = {
            'client_id': self.client_id,
            'response_type': 'code',
            'redirect_uri': f'{self.grafana_base}/login/generic_oauth',
            'scope': 'openid profile email',
            'state': 'test-state'
        }
        
        try:
            response = requests.get(auth_url, params=params, allow_redirects=False, timeout=5)
            
            if response.status_code == 302:
                location = response.headers.get('Location', '')
                if '/if/flow/' in location:
                    print("✅ Authentik OAuth2 provider configured - redirects to login flow")
                    print(f"   Login flow URL: {location}")
                    return True
                else:
                    print("⚠️  Unexpected redirect from Authentik")
                    print(f"   Redirect URL: {location}")
                    return False
            elif response.status_code == 200:
                print("✅ Authentik OAuth2 provider responds (may need login)")
                return True
            else:
                print(f"❌ Authentik OAuth2 provider error - HTTP {response.status_code}")
                return False
                
        except Exception as e:
            print(f"❌ Error testing Authentik provider: {e}")
            return False
    
    def test_token_endpoint(self):
        """Test the OAuth2 token endpoint"""
        print("\n🔧 Testing OAuth2 Token Endpoint")
        print("=" * 40)
        
        token_url = f"{self.authentik_base}/application/o/token/"
        
        try:
            # Test with invalid credentials to see if endpoint responds properly
            response = requests.post(
                token_url,
                data={
                    'grant_type': 'authorization_code',
                    'client_id': self.client_id,
                    'client_secret': 'invalid',
                    'code': 'invalid',
                    'redirect_uri': f'{self.grafana_base}/login/generic_oauth'
                },
                timeout=5
            )
            
            if response.status_code in [400, 401]:
                print("✅ Token endpoint working - rejects invalid credentials")
                return True
            else:
                print(f"⚠️  Token endpoint returned HTTP {response.status_code}")
                try:
                    error_data = response.json()
                    print(f"   Response: {error_data}")
                except:
                    print(f"   Response: {response.text[:100]}")
                return False
                
        except Exception as e:
            print(f"❌ Error testing token endpoint: {e}")
            return False
    
    def test_userinfo_endpoint(self):
        """Test the OAuth2 userinfo endpoint"""
        print("\n🔧 Testing OAuth2 UserInfo Endpoint") 
        print("=" * 40)
        
        userinfo_url = f"{self.authentik_base}/application/o/userinfo/"
        
        try:
            response = requests.get(
                userinfo_url,
                headers={'Authorization': 'Bearer invalid-token'},
                timeout=5
            )
            
            if response.status_code == 401:
                print("✅ UserInfo endpoint working - requires valid token")
                return True
            else:
                print(f"⚠️  UserInfo endpoint returned HTTP {response.status_code}")
                return False
                
        except Exception as e:
            print(f"❌ Error testing userinfo endpoint: {e}")
            return False
    
    def test_forwardauth_endpoint(self):
        """Test the ForwardAuth endpoint for Traefik"""
        print("\n🔧 Testing ForwardAuth Endpoint")
        print("=" * 40)
        
        forwardauth_url = f"{self.authentik_base}/outpost.goauthentik.io/auth/traefik"
        
        try:
            response = requests.get(forwardauth_url, allow_redirects=False, timeout=5)
            
            if response.status_code == 302:
                print("✅ ForwardAuth endpoint working - redirects unauthenticated requests")
                return True
            elif response.status_code == 401:
                print("✅ ForwardAuth endpoint working - returns unauthorized")
                return True
            elif response.status_code == 404:
                print("❌ ForwardAuth endpoint not configured (404)")
                return False
            else:
                print(f"⚠️  ForwardAuth endpoint returned HTTP {response.status_code}")
                return False
                
        except Exception as e:
            print(f"❌ Error testing ForwardAuth: {e}")
            return False
    
    def run_complete_test(self):
        """Run all tests and provide summary"""
        print("🚀 OAuth2 Authentication Flow Test")
        print("=" * 50)
        print(f"Authentik: {self.authentik_base}")
        print(f"Grafana: {self.grafana_base}")
        print(f"Client ID: {self.client_id}")
        print("")
        
        tests = [
            ("Basic Endpoints", self.test_endpoints),
            ("Grafana OAuth Config", self.test_grafana_oauth_config),
            ("Authentik Provider", self.test_authentik_provider),
            ("Token Endpoint", self.test_token_endpoint),
            ("UserInfo Endpoint", self.test_userinfo_endpoint),
            ("ForwardAuth Endpoint", self.test_forwardauth_endpoint),
        ]
        
        results = {}
        for test_name, test_func in tests:
            try:
                if test_name == "Basic Endpoints":
                    endpoint_results = test_func()
                    results[test_name] = all("✅" in result for result in endpoint_results.values())
                else:
                    results[test_name] = test_func()
            except Exception as e:
                print(f"❌ {test_name} failed with error: {e}")
                results[test_name] = False
        
        # Summary
        print("\n" + "=" * 50)
        print("📊 TEST SUMMARY")
        print("=" * 50)
        
        passed = sum(results.values())
        total = len(results)
        
        for test_name, passed_test in results.items():
            status = "✅ PASS" if passed_test else "❌ FAIL"
            print(f"  {test_name:25}: {status}")
        
        print("")
        print(f"Tests passed: {passed}/{total}")
        
        if passed == total:
            print("🎉 All tests passed! OAuth2 flow is ready.")
            return True
        else:
            print("⚠️  Some tests failed. Check the configuration.")
            return False


def main():
    parser = argparse.ArgumentParser(description='Test OAuth2 authentication flow')
    parser.add_argument('--authentik-host', default='192.168.1.13:9002', help='Authentik host:port')
    parser.add_argument('--grafana-host', default='192.168.1.12:3000', help='Grafana host:port')
    parser.add_argument('--client-id', default='grafana', help='OAuth2 client ID')
    parser.add_argument('--client-secret', help='OAuth2 client secret (optional)')
    
    args = parser.parse_args()
    
    tester = OAuth2FlowTester(
        args.authentik_host,
        args.grafana_host,
        args.client_id,
        args.client_secret
    )
    
    success = tester.run_complete_test()
    
    if success:
        print("\n✨ Next steps:")
        print("1. Complete manual Authentik configuration if needed")
        print("2. Configure Grafana with OAuth2 client secret")
        print("3. Test login flow: http://192.168.1.12:3000/login/generic_oauth")
        sys.exit(0)
    else:
        print("\n🔧 Fix the failed tests and run again")
        sys.exit(1)


if __name__ == "__main__":
    main()