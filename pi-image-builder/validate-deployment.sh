#!/bin/bash
# Comprehensive Deployment Validation Script
# Tests all redundancies and failover mechanisms

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
SSH_KEY="${SSH_KEY:-$HOME/.ssh/pi_ed25519}"
VALIDATION_LOG="validation-$(date +%Y%m%d-%H%M%S).log"

echo -e "${BLUE}========================================${NC}" | tee "$VALIDATION_LOG"
echo -e "${BLUE}   Pi Cluster Validation Suite${NC}" | tee -a "$VALIDATION_LOG"
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

# Test 1: Network Discovery
test_network_discovery() {
    echo -e "\n${YELLOW}1. Network Discovery Tests${NC}" | tee -a "$VALIDATION_LOG"
    
    # Test mDNS resolution
    for hostname in pi-a pi-b pi-c pi-d; do
        if ping -c 1 -W 2 "${hostname}.local" &>/dev/null; then
            test_result "mDNS resolution for ${hostname}.local" "pass"
        else
            test_result "mDNS resolution for ${hostname}.local" "fail" "Cannot resolve hostname"
        fi
    done
    
    # Test avahi browsing
    if command -v avahi-browse &>/dev/null; then
        if avahi-browse -t -r _workstation._tcp 2>/dev/null | grep -q "pi-"; then
            test_result "Avahi service discovery" "pass"
        else
            test_result "Avahi service discovery" "warn" "No Pi services found"
        fi
    else
        test_result "Avahi service discovery" "warn" "avahi-browse not installed"
    fi
}

# Test 2: SSH Access Redundancy
test_ssh_redundancy() {
    echo -e "\n${YELLOW}2. SSH Access Redundancy Tests${NC}" | tee -a "$VALIDATION_LOG"
    
    for hostname in pi-a pi-b pi-c pi-d; do
        # Test primary SSH with key
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$SSH_KEY" \
            "pi@${hostname}.local" "echo OK" &>/dev/null; then
            test_result "SSH key auth to $hostname" "pass"
        else
            test_result "SSH key auth to $hostname" "fail" "Key authentication failed"
        fi
        
        # Test recovery user
        if sshpass -p "RecoveryAccess2024!" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            "recovery@${hostname}.local" "echo OK" &>/dev/null; then
            test_result "Recovery user access to $hostname" "pass"
        else
            test_result "Recovery user access to $hostname" "warn" "Recovery login not working"
        fi
        
        # Test Tailscale SSH if available
        if command -v tailscale &>/dev/null && tailscale status &>/dev/null; then
            if tailscale ping "$hostname" &>/dev/null; then
                test_result "Tailscale connectivity to $hostname" "pass"
            else
                test_result "Tailscale connectivity to $hostname" "warn" "Tailscale not connected"
            fi
        fi
    done
}

# Test 3: Time Synchronization
test_time_sync() {
    echo -e "\n${YELLOW}3. Time Synchronization Tests${NC}" | tee -a "$VALIDATION_LOG"
    
    for hostname in pi-a pi-b pi-c pi-d; do
        # Check chrony status
        if ssh -o ConnectTimeout=5 "$hostname" "chronyc tracking" &>/dev/null; then
            # Get time offset
            offset=$(ssh "$hostname" "chronyc tracking | grep 'System time' | awk '{print \$4}'" 2>/dev/null || echo "999")
            offset_ms=$(echo "$offset * 1000" | bc 2>/dev/null || echo "999")
            
            # Check if within 100ms (CLAUDE.md requirement)
            if (( $(echo "$offset_ms < 100" | bc -l 2>/dev/null || echo 0) )); then
                test_result "Time sync on $hostname (${offset}s)" "pass"
            else
                test_result "Time sync on $hostname (${offset}s)" "fail" "Drift exceeds 100ms limit"
            fi
            
            # Check stratum
            stratum=$(ssh "$hostname" "chronyc tracking | grep 'Stratum' | awk '{print \$3}'" 2>/dev/null || echo "99")
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

# Test 4: Service Health
test_service_health() {
    echo -e "\n${YELLOW}4. Service Health Tests${NC}" | tee -a "$VALIDATION_LOG"
    
    # Test Prometheus on pi-a
    if curl -sf -o /dev/null "http://pi-a.local:9090/-/ready"; then
        test_result "Prometheus service" "pass"
    else
        test_result "Prometheus service" "fail" "Not responding"
    fi
    
    # Test Grafana on pi-a
    if curl -sf -o /dev/null "http://pi-a.local:3000/api/health"; then
        test_result "Grafana service" "pass"
    else
        test_result "Grafana service" "fail" "Not responding"
    fi
    
    # Test Loki on pi-a
    if curl -sf -o /dev/null "http://pi-a.local:3100/ready"; then
        test_result "Loki service" "pass"
    else
        test_result "Loki service" "fail" "Not responding"
    fi
    
    # Test Node Exporters
    for hostname in pi-a pi-b pi-c pi-d; do
        if curl -sf -o /dev/null "http://${hostname}.local:9100/metrics"; then
            test_result "Node exporter on $hostname" "pass"
        else
            test_result "Node exporter on $hostname" "warn" "Not responding"
        fi
    done
}

# Test 5: Failover Mechanisms
test_failover() {
    echo -e "\n${YELLOW}5. Failover Mechanism Tests${NC}" | tee -a "$VALIDATION_LOG"
    
    # Test network failover script exists
    for hostname in pi-a pi-b pi-c pi-d; do
        if ssh "$hostname" "test -x /usr/local/bin/check-network.sh" 2>/dev/null; then
            test_result "Network failover script on $hostname" "pass"
        else
            test_result "Network failover script on $hostname" "warn" "Script not found"
        fi
    done
    
    # Test WiFi availability
    for hostname in pi-a pi-b pi-c pi-d; do
        wifi_status=$(ssh "$hostname" "ip link show wlan0 2>/dev/null | grep -o 'state [A-Z]*' | awk '{print \$2}'" || echo "NONE")
        if [ "$wifi_status" = "UP" ]; then
            test_result "WiFi backup on $hostname" "pass"
        elif [ "$wifi_status" = "DOWN" ]; then
            test_result "WiFi backup on $hostname" "warn" "Interface down"
        else
            test_result "WiFi backup on $hostname" "warn" "No WiFi interface"
        fi
    done
}

# Test 6: Security Hardening
test_security() {
    echo -e "\n${YELLOW}6. Security Tests${NC}" | tee -a "$VALIDATION_LOG"
    
    for hostname in pi-a pi-b pi-c pi-d; do
        # Check UFW status
        if ssh "$hostname" "sudo ufw status" 2>/dev/null | grep -q "Status: active"; then
            test_result "Firewall enabled on $hostname" "pass"
        else
            test_result "Firewall enabled on $hostname" "fail" "UFW not active"
        fi
        
        # Check fail2ban
        if ssh "$hostname" "systemctl is-active fail2ban" 2>/dev/null | grep -q "active"; then
            test_result "fail2ban active on $hostname" "pass"
        else
            test_result "fail2ban active on $hostname" "warn" "Service not running"
        fi
        
        # Check unattended upgrades
        if ssh "$hostname" "test -f /etc/apt/apt.conf.d/20auto-upgrades" 2>/dev/null; then
            test_result "Auto-updates configured on $hostname" "pass"
        else
            test_result "Auto-updates configured on $hostname" "warn" "Not configured"
        fi
    done
}

# Test 7: Backup Mechanisms
test_backup() {
    echo -e "\n${YELLOW}7. Backup Mechanism Tests${NC}" | tee -a "$VALIDATION_LOG"
    
    for hostname in pi-a pi-b pi-c pi-d; do
        # Check USB backup script
        if ssh "$hostname" "test -x /usr/local/bin/usb-backup.sh" 2>/dev/null; then
            test_result "USB backup script on $hostname" "pass"
        else
            test_result "USB backup script on $hostname" "warn" "Script not found"
        fi
        
        # Check backup directory
        if ssh "$hostname" "test -d /home/pi/backup" 2>/dev/null; then
            test_result "Backup directory on $hostname" "pass"
        else
            test_result "Backup directory on $hostname" "warn" "Directory not found"
        fi
    done
}

# Test 8: Container Runtime
test_containers() {
    echo -e "\n${YELLOW}8. Container Runtime Tests${NC}" | tee -a "$VALIDATION_LOG"
    
    for hostname in pi-a pi-b pi-c pi-d; do
        # Check Podman installation
        if ssh "$hostname" "podman --version" &>/dev/null; then
            test_result "Podman installed on $hostname" "pass"
        else
            test_result "Podman installed on $hostname" "fail" "Podman not found"
        fi
        
        # Check systemd integration
        if ssh "$hostname" "test -d /etc/containers/systemd" 2>/dev/null; then
            test_result "Quadlet support on $hostname" "pass"
        else
            test_result "Quadlet support on $hostname" "warn" "Directory not found"
        fi
        
        # Check container directories
        if ssh "$hostname" "test -d /home/pi/.config/containers/systemd" 2>/dev/null; then
            test_result "User container config on $hostname" "pass"
        else
            test_result "User container config on $hostname" "warn" "Not configured"
        fi
    done
}

# Test 9: Performance Baseline
test_performance() {
    echo -e "\n${YELLOW}9. Performance Baseline Tests${NC}" | tee -a "$VALIDATION_LOG"
    
    for hostname in pi-a pi-b pi-c pi-d; do
        # Test SSH response time
        start_time=$(date +%s%N)
        ssh -o ConnectTimeout=5 "$hostname" "echo OK" &>/dev/null
        end_time=$(date +%s%N)
        response_time=$(( (end_time - start_time) / 1000000 ))
        
        if [ $response_time -lt 1000 ]; then
            test_result "SSH response time on $hostname (${response_time}ms)" "pass"
        else
            test_result "SSH response time on $hostname (${response_time}ms)" "warn" "High latency"
        fi
        
        # Check system load
        load=$(ssh "$hostname" "uptime | awk -F'load average:' '{print \$2}' | awk '{print \$1}' | tr -d ','" 2>/dev/null || echo "999")
        if (( $(echo "$load < 2" | bc -l 2>/dev/null || echo 0) )); then
            test_result "System load on $hostname ($load)" "pass"
        else
            test_result "System load on $hostname ($load)" "warn" "High load"
        fi
    done
}

# Main execution
main() {
    # Run all test suites
    test_network_discovery
    test_ssh_redundancy
    test_time_sync
    test_service_health
    test_failover
    test_security
    test_backup
    test_containers
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
    
    # Overall status
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ Deployment validation PASSED${NC}" | tee -a "$VALIDATION_LOG"
        echo "  All critical systems are operational" | tee -a "$VALIDATION_LOG"
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