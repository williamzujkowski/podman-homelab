#!/bin/bash
# Enhanced Validation Script for Static DHCP Deployment
# Tests static IP assignments and all redundancy mechanisms

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

# Configuration
STATIC_CONFIG="static-dhcp-config.json"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/pi_ed25519}"
VALIDATION_LOG="validation-static-$(date +%Y%m%d-%H%M%S).log"

echo -e "${BLUE}========================================${NC}" | tee "$VALIDATION_LOG"
echo -e "${BLUE}   Pi Cluster Validation (Static DHCP)${NC}" | tee -a "$VALIDATION_LOG"
echo -e "${BLUE}   $(date)${NC}" | tee -a "$VALIDATION_LOG"
echo -e "${BLUE}========================================${NC}" | tee -a "$VALIDATION_LOG"

# Helper function for test results
test_result() {
    local test_name="$1"
    local status="$2"  # pass, fail, warn
    local message="${3:-}"
    
    case "$status" in
        pass)
            echo -e "  ${GREEN}✓${NC} $test_name" | tee -a "$VALIDATION_LOG"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            ;;
        fail)
            echo -e "  ${RED}✗${NC} $test_name" | tee -a "$VALIDATION_LOG"
            [ -n "$message" ] && echo "    └─ $message" | tee -a "$VALIDATION_LOG"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            ;;
        warn)
            echo -e "  ${YELLOW}⚠${NC} $test_name" | tee -a "$VALIDATION_LOG"
            [ -n "$message" ] && echo "    └─ $message" | tee -a "$VALIDATION_LOG"
            TESTS_WARNED=$((TESTS_WARNED + 1))
            ;;
    esac
}

# Test 1: Static DHCP Configuration
test_static_dhcp_config() {
    echo -e "\n${YELLOW}1. Static DHCP Configuration Tests${NC}" | tee -a "$VALIDATION_LOG"
    
    # Check config file exists
    if [ ! -f "$STATIC_CONFIG" ]; then
        test_result "Static DHCP config file" "fail" "File not found: $STATIC_CONFIG"
        return
    else
        test_result "Static DHCP config file" "pass"
    fi
    
    # Validate each static lease
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value.ip) \(.value.mac)"' "$STATIC_CONFIG" | \
    while IFS=' ' read -r hostname ip mac; do
        # Check IP format
        if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            test_result "IP format for $hostname" "pass"
        else
            test_result "IP format for $hostname" "fail" "Invalid IP: $ip"
        fi
        
        # Check MAC status
        if [ "$mac" = "PENDING" ]; then
            test_result "MAC address for $hostname" "warn" "Not yet collected"
        elif [[ "$mac" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
            test_result "MAC address for $hostname" "pass"
        else
            test_result "MAC address for $hostname" "fail" "Invalid MAC: $mac"
        fi
    done
}

# Test 2: Static IP Connectivity
test_static_ip_connectivity() {
    echo -e "\n${YELLOW}2. Static IP Connectivity Tests${NC}" | tee -a "$VALIDATION_LOG"
    
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value.ip)"' "$STATIC_CONFIG" | \
    while IFS=' ' read -r hostname ip; do
        # Ping test
        if ping -c 1 -W 2 "$ip" &>/dev/null; then
            test_result "Ping $hostname at $ip" "pass"
            
            # Verify hostname matches
            actual_hostname=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -i "$SSH_KEY" \
                "pi@$ip" "hostname" 2>/dev/null || echo "unknown")
            
            if [ "$actual_hostname" = "$hostname" ]; then
                test_result "Hostname verification for $ip" "pass"
            else
                test_result "Hostname verification for $ip" "fail" "Expected $hostname, got $actual_hostname"
            fi
        else
            test_result "Ping $hostname at $ip" "fail" "No response"
        fi
    done
}

# Test 3: DHCP Lease Verification
test_dhcp_leases() {
    echo -e "\n${YELLOW}3. DHCP Lease Verification Tests${NC}" | tee -a "$VALIDATION_LOG"
    
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value.ip) \(.value.mac)"' "$STATIC_CONFIG" | \
    while IFS=' ' read -r hostname expected_ip mac; do
        if [ "$mac" != "PENDING" ] && [ "$mac" != "null" ]; then
            # Get actual IP via DHCP
            actual_ip=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -i "$SSH_KEY" \
                "pi@$expected_ip" "ip addr show eth0 | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1" 2>/dev/null || echo "")
            
            if [ "$actual_ip" = "$expected_ip" ]; then
                test_result "DHCP lease for $hostname" "pass"
            elif [ -n "$actual_ip" ]; then
                test_result "DHCP lease for $hostname" "fail" "Expected $expected_ip, got $actual_ip"
            else
                test_result "DHCP lease for $hostname" "fail" "Could not determine IP"
            fi
        else
            test_result "DHCP lease for $hostname" "warn" "MAC not configured"
        fi
    done
}

# Test 4: Network Path Redundancy
test_network_paths() {
    echo -e "\n${YELLOW}4. Network Path Redundancy Tests${NC}" | tee -a "$VALIDATION_LOG"
    
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value.ip)"' "$STATIC_CONFIG" | \
    while IFS=' ' read -r hostname ip; do
        # Test multiple access methods
        
        # Method 1: Direct IP
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 -i "$SSH_KEY" "pi@$ip" "echo OK" &>/dev/null; then
            test_result "Direct IP access to $hostname" "pass"
        else
            test_result "Direct IP access to $hostname" "fail"
        fi
        
        # Method 2: Hostname.local
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 -i "$SSH_KEY" "pi@${hostname}.local" "echo OK" &>/dev/null; then
            test_result "mDNS access to $hostname" "pass"
        else
            test_result "mDNS access to $hostname" "warn" "mDNS not working"
        fi
        
        # Method 3: Check for WiFi backup
        wifi_status=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 -i "$SSH_KEY" \
            "pi@$ip" "ip link show wlan0 2>/dev/null | grep -o 'state [A-Z]*' | awk '{print \$2}'" 2>/dev/null || echo "NONE")
        
        if [ "$wifi_status" = "UP" ]; then
            test_result "WiFi backup on $hostname" "pass"
        else
            test_result "WiFi backup on $hostname" "warn" "WiFi not configured"
        fi
    done
}

# Test 5: DNS Resolution
test_dns_resolution() {
    echo -e "\n${YELLOW}5. DNS Resolution Tests${NC}" | tee -a "$VALIDATION_LOG"
    
    # Check if hosts file entries exist
    if [ -f "hosts.static" ]; then
        test_result "Static hosts file generated" "pass"
        
        # Check if applied to system
        jq -r '.static_leases | keys[]' "$STATIC_CONFIG" | while read -r hostname; do
            if grep -q "$hostname" /etc/hosts; then
                test_result "/etc/hosts entry for $hostname" "pass"
            else
                test_result "/etc/hosts entry for $hostname" "warn" "Not in /etc/hosts"
            fi
        done
    else
        test_result "Static hosts file" "warn" "Not generated - run ./discover-pis-static.sh"
    fi
    
    # Test resolution methods
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value.ip)"' "$STATIC_CONFIG" | \
    while IFS=' ' read -r hostname ip; do
        # Method 1: Direct resolution
        resolved_ip=$(getent hosts "$hostname" 2>/dev/null | awk '{print $1}')
        if [ "$resolved_ip" = "$ip" ]; then
            test_result "Direct resolution of $hostname" "pass"
        elif [ -n "$resolved_ip" ]; then
            test_result "Direct resolution of $hostname" "warn" "Resolved to $resolved_ip instead of $ip"
        else
            test_result "Direct resolution of $hostname" "warn" "Not resolvable"
        fi
    done
}

# Test 6: Service Accessibility
test_service_access() {
    echo -e "\n${YELLOW}6. Service Accessibility Tests${NC}" | tee -a "$VALIDATION_LOG"
    
    # Test services based on role
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value.ip) \(.value.role)"' "$STATIC_CONFIG" | \
    while IFS=' ' read -r hostname ip role; do
        case "$role" in
            monitoring)
                # Test Prometheus
                if curl -sf -o /dev/null "http://$ip:9090/-/ready"; then
                    test_result "Prometheus on $hostname" "pass"
                else
                    test_result "Prometheus on $hostname" "fail" "Not responding"
                fi
                
                # Test Grafana
                if curl -sf -o /dev/null "http://$ip:3000/api/health"; then
                    test_result "Grafana on $hostname" "pass"
                else
                    test_result "Grafana on $hostname" "fail" "Not responding"
                fi
                
                # Test Loki
                if curl -sf -o /dev/null "http://$ip:3100/ready"; then
                    test_result "Loki on $hostname" "pass"
                else
                    test_result "Loki on $hostname" "fail" "Not responding"
                fi
                ;;
                
            ingress)
                # Test Traefik
                if curl -sf -o /dev/null "http://$ip:8080/ping"; then
                    test_result "Traefik on $hostname" "pass"
                else
                    test_result "Traefik on $hostname" "warn" "Not configured"
                fi
                ;;
                
            *)
                # Test node exporter (should be on all)
                if curl -sf -o /dev/null "http://$ip:9100/metrics"; then
                    test_result "Node exporter on $hostname" "pass"
                else
                    test_result "Node exporter on $hostname" "warn" "Not responding"
                fi
                ;;
        esac
    done
}

# Test 7: Time Synchronization
test_time_sync() {
    echo -e "\n${YELLOW}7. Time Synchronization Tests${NC}" | tee -a "$VALIDATION_LOG"
    
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value.ip)"' "$STATIC_CONFIG" | \
    while IFS=' ' read -r hostname ip; do
        # Check chrony status
        if ssh -o ConnectTimeout=3 -i "$SSH_KEY" "pi@$ip" "chronyc tracking" &>/dev/null; then
            # Get time offset
            offset=$(ssh "pi@$ip" "chronyc tracking | grep 'System time' | awk '{print \$4}'" 2>/dev/null || echo "999")
            offset_ms=$(echo "$offset * 1000" | bc 2>/dev/null || echo "999")
            
            # Check if within 100ms (CLAUDE.md requirement)
            if (( $(echo "$offset_ms < 100" | bc -l 2>/dev/null || echo 0) )); then
                test_result "Time sync on $hostname (${offset}s)" "pass"
            else
                test_result "Time sync on $hostname (${offset}s)" "fail" "Drift exceeds 100ms limit"
            fi
            
            # Check stratum
            stratum=$(ssh "pi@$ip" "chronyc tracking | grep 'Stratum' | awk '{print \$3}'" 2>/dev/null || echo "99")
            if [ "$stratum" -le 3 ]; then
                test_result "Stratum level on $hostname ($stratum)" "pass"
            else
                test_result "Stratum level on $hostname ($stratum)" "fail" "Exceeds stratum 3 limit"
            fi
        else
            test_result "Chrony service on $hostname" "fail" "Cannot check time sync"
        fi
    done
}

# Test 8: SSH Key Authentication
test_ssh_keys() {
    echo -e "\n${YELLOW}8. SSH Key Authentication Tests${NC}" | tee -a "$VALIDATION_LOG"
    
    # Test primary key
    if [ -f "$SSH_KEY" ]; then
        test_result "Primary SSH key exists" "pass"
    else
        test_result "Primary SSH key exists" "fail" "$SSH_KEY not found"
    fi
    
    # Test backup keys
    for key in ~/.ssh/id_ed25519 ~/.ssh/id_rsa; do
        if [ -f "$key" ]; then
            test_result "Backup key $(basename $key)" "pass"
        else
            test_result "Backup key $(basename $key)" "warn" "Not found"
        fi
    done
    
    # Test SSH access with each Pi
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value.ip)"' "$STATIC_CONFIG" | \
    while IFS=' ' read -r hostname ip; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 -o PasswordAuthentication=no \
            -i "$SSH_KEY" "pi@$ip" "echo OK" &>/dev/null; then
            test_result "Key auth to $hostname" "pass"
        else
            test_result "Key auth to $hostname" "fail" "Key authentication failed"
        fi
    done
}

# Test 9: Ansible Connectivity
test_ansible() {
    echo -e "\n${YELLOW}9. Ansible Connectivity Tests${NC}" | tee -a "$VALIDATION_LOG"
    
    # Check for Ansible inventory
    if [ -f "../ansible/inventories/prod/hosts.yml.static" ]; then
        test_result "Ansible static inventory exists" "pass"
        
        # Test ansible ping
        if command -v ansible &>/dev/null; then
            if ansible -i "../ansible/inventories/prod/hosts.yml.static" pis -m ping &>/dev/null; then
                test_result "Ansible ping to all hosts" "pass"
            else
                test_result "Ansible ping to all hosts" "fail" "Some hosts not reachable"
            fi
        else
            test_result "Ansible connectivity" "warn" "Ansible not installed"
        fi
    else
        test_result "Ansible inventory" "warn" "Static inventory not generated"
    fi
}

# Test 10: Performance with Static IPs
test_performance() {
    echo -e "\n${YELLOW}10. Performance Tests (Static IPs)${NC}" | tee -a "$VALIDATION_LOG"
    
    # Test discovery speed
    echo "  Testing discovery performance..."
    start_time=$(date +%s%N)
    
    # Quick check of all static IPs
    jq -r '.static_leases | to_entries[] | .value.ip' "$STATIC_CONFIG" | \
    while read -r ip; do
        timeout 1 nc -zv "$ip" 22 &>/dev/null
    done
    
    end_time=$(date +%s%N)
    discovery_time=$(( (end_time - start_time) / 1000000 ))
    
    if [ $discovery_time -lt 5000 ]; then
        test_result "Discovery speed (${discovery_time}ms)" "pass"
    elif [ $discovery_time -lt 10000 ]; then
        test_result "Discovery speed (${discovery_time}ms)" "warn" "Slower than expected"
    else
        test_result "Discovery speed (${discovery_time}ms)" "fail" "Too slow"
    fi
    
    # Test SSH response times
    jq -r '.static_leases | to_entries[] | "\(.key) \(.value.ip)"' "$STATIC_CONFIG" | \
    while IFS=' ' read -r hostname ip; do
        start_time=$(date +%s%N)
        ssh -o ConnectTimeout=2 -i "$SSH_KEY" "pi@$ip" "echo OK" &>/dev/null
        end_time=$(date +%s%N)
        response_time=$(( (end_time - start_time) / 1000000 ))
        
        if [ $response_time -lt 500 ]; then
            test_result "SSH to $hostname (${response_time}ms)" "pass"
        elif [ $response_time -lt 1000 ]; then
            test_result "SSH to $hostname (${response_time}ms)" "warn" "High latency"
        else
            test_result "SSH to $hostname (${response_time}ms)" "fail" "Very high latency"
        fi
    done
}

# Main execution
main() {
    # Check for static config
    if [ ! -f "$STATIC_CONFIG" ]; then
        echo -e "${RED}Error: Static DHCP configuration not found!${NC}"
        echo "Run: ./manage-static-dhcp.sh"
        exit 1
    fi
    
    # Run all test suites
    test_static_dhcp_config
    test_static_ip_connectivity
    test_dhcp_leases
    test_network_paths
    test_dns_resolution
    test_service_access
    test_time_sync
    test_ssh_keys
    test_ansible
    test_performance
    
    # Generate summary
    echo -e "\n${BLUE}========================================${NC}" | tee -a "$VALIDATION_LOG"
    echo -e "${BLUE}   Validation Summary${NC}" | tee -a "$VALIDATION_LOG"
    echo -e "${BLUE}========================================${NC}" | tee -a "$VALIDATION_LOG"
    echo "" | tee -a "$VALIDATION_LOG"
    
    total_tests=$((TESTS_PASSED + TESTS_FAILED + TESTS_WARNED))
    
    echo "Total Tests: $total_tests" | tee -a "$VALIDATION_LOG"
    echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}" | tee -a "$VALIDATION_LOG"
    echo -e "  ${YELLOW}Warnings: $TESTS_WARNED${NC}" | tee -a "$VALIDATION_LOG"
    echo -e "  ${RED}Failed: $TESTS_FAILED${NC}" | tee -a "$VALIDATION_LOG"
    echo "" | tee -a "$VALIDATION_LOG"
    
    # Show static IP summary
    echo -e "${YELLOW}Static IP Assignments:${NC}" | tee -a "$VALIDATION_LOG"
    jq -r '.static_leases | to_entries[] | "  \(.key): \(.value.ip) [\(.value.role)]"' "$STATIC_CONFIG" | tee -a "$VALIDATION_LOG"
    echo "" | tee -a "$VALIDATION_LOG"
    
    # Overall status
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ Static DHCP deployment validation PASSED${NC}" | tee -a "$VALIDATION_LOG"
        echo "  All systems operational with static IPs" | tee -a "$VALIDATION_LOG"
    elif [ $TESTS_FAILED -lt 5 ]; then
        echo -e "${YELLOW}⚠ Deployment validation PARTIAL${NC}" | tee -a "$VALIDATION_LOG"
        echo "  Some issues detected, but system is functional" | tee -a "$VALIDATION_LOG"
    else
        echo -e "${RED}✗ Deployment validation FAILED${NC}" | tee -a "$VALIDATION_LOG"
        echo "  Critical issues detected - review log" | tee -a "$VALIDATION_LOG"
    fi
    
    echo "" | tee -a "$VALIDATION_LOG"
    echo "Full validation log: $VALIDATION_LOG" | tee -a "$VALIDATION_LOG"
    
    # Return appropriate exit code
    if [ $TESTS_FAILED -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Run validation
main "$@"