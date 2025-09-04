#!/bin/bash
# Authentik Local Test Script

set -e

echo "🧪 Testing Authentik Deployment Locally"
echo "======================================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Clean up function
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    docker-compose -f test/docker-compose.yml down -v
}

# Set trap for cleanup
trap cleanup EXIT

# Change to repo root
cd "$(dirname "$0")/.."

echo -e "\n${YELLOW}Starting services...${NC}"
docker-compose -f test/docker-compose.yml up -d

echo -e "\n${YELLOW}Waiting for PostgreSQL...${NC}"
timeout 60 bash -c 'until docker exec authentik-postgres pg_isready -U authentik > /dev/null 2>&1; do sleep 2; done'
echo -e "${GREEN}✓ PostgreSQL ready${NC}"

echo -e "\n${YELLOW}Waiting for Redis...${NC}"
timeout 30 bash -c 'until docker exec authentik-redis redis-cli ping > /dev/null 2>&1; do sleep 2; done'
echo -e "${GREEN}✓ Redis ready${NC}"

echo -e "\n${YELLOW}Waiting for Authentik Server (this may take 2-3 minutes)...${NC}"
timeout 180 bash -c 'until curl -sf http://localhost:9000/api/v3/root/config/ > /dev/null 2>&1; do echo -n "."; sleep 5; done'
echo -e "\n${GREEN}✓ Authentik Server ready${NC}"

echo -e "\n${YELLOW}Running validation tests...${NC}"

# Test 1: API Health
echo -n "Testing API health endpoint... "
if curl -sf http://localhost:9000/api/v3/root/config/ > /dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
    exit 1
fi

# Test 2: Database connectivity
echo -n "Testing database connectivity... "
if docker exec authentik-postgres psql -U authentik -d authentik -c "SELECT 1" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
    exit 1
fi

# Test 3: Redis connectivity
echo -n "Testing Redis connectivity... "
if docker exec authentik-redis redis-cli ping | grep -q PONG; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
    exit 1
fi

# Test 4: Worker running
echo -n "Testing worker container... "
if docker ps | grep -q authentik-worker; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
    exit 1
fi

# Test 5: Web interface
echo -n "Testing web interface... "
if curl -sf http://localhost:9000/if/flow/initial-setup/ > /dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
    exit 1
fi

# Test 6: Memory usage
echo -e "\n${YELLOW}Checking resource usage...${NC}"
docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}" | grep authentik || true

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ All tests passed!${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "\n${YELLOW}Authentik is running at:${NC} http://localhost:9000"
echo -e "${YELLOW}Default credentials:${NC} akadmin / <set on first login>"

echo -e "\n${YELLOW}To access container logs:${NC}"
echo "docker logs authentik-server"
echo "docker logs authentik-worker"

echo -e "\n${YELLOW}To stop the test environment, press Ctrl+C${NC}"
echo -e "${YELLOW}The environment will be automatically cleaned up${NC}"

# Keep running until interrupted
read -r -p "Press Enter to stop and clean up..." 