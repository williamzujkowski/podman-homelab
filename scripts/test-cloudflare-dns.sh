#!/usr/bin/env bash

# Test Cloudflare DNS API access for Let's Encrypt
# This verifies the API token has the correct permissions

API_TOKEN="Z3vYaDL2Ov6K5iqURRdk9bGMvs_9KeMcSpVogEqT"
DOMAIN="grenlan.com"

echo "Testing Cloudflare API Token permissions..."
echo ""

# Test 1: Verify token validity
echo -n "1. Testing token validity... "
response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
     -H "Authorization: Bearer $API_TOKEN" \
     -H "Content-Type: application/json")

if echo "$response" | grep -q '"success":true'; then
    echo "✓ Token is valid"
else
    echo "✗ Token validation failed"
    echo "Response: $response"
    exit 1
fi

# Test 2: List zones to find our domain
echo -n "2. Finding zone ID for $DOMAIN... "
zones=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
     -H "Authorization: Bearer $API_TOKEN" \
     -H "Content-Type: application/json")

zone_id=$(echo "$zones" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)

if [ -n "$zone_id" ]; then
    echo "✓ Found zone: $zone_id"
else
    echo "✗ Could not find zone"
    echo "Response: $zones"
    exit 1
fi

# Test 3: Check DNS record permissions
echo -n "3. Testing DNS record permissions... "
dns_records=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
     -H "Authorization: Bearer $API_TOKEN" \
     -H "Content-Type: application/json")

if echo "$dns_records" | grep -q '"success":true'; then
    echo "✓ Can read DNS records"
else
    echo "✗ Cannot read DNS records"
    echo "Response: $dns_records"
    exit 1
fi

# Test 4: Test creating a TXT record (for DNS-01 challenge)
echo -n "4. Testing DNS record creation (TXT record)... "
test_record="_acme-test.homelab.$DOMAIN"
create_response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
     -H "Authorization: Bearer $API_TOKEN" \
     -H "Content-Type: application/json" \
     --data "{\"type\":\"TXT\",\"name\":\"$test_record\",\"content\":\"test-$(date +%s)\",\"ttl\":120}")

if echo "$create_response" | grep -q '"success":true'; then
    echo "✓ Can create DNS records"
    
    # Clean up test record
    record_id=$(echo "$create_response" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    if [ -n "$record_id" ]; then
        curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
             -H "Authorization: Bearer $API_TOKEN" \
             -H "Content-Type: application/json" > /dev/null
        echo "   (Test record cleaned up)"
    fi
else
    echo "✗ Cannot create DNS records"
    echo "Response: $create_response"
    echo ""
    echo "This token needs 'Zone:DNS:Edit' permission for $DOMAIN"
    exit 1
fi

echo ""
echo "✅ All tests passed! Your Cloudflare API token has the correct permissions for Let's Encrypt DNS-01 challenge."