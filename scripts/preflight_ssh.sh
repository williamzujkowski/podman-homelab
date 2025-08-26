#!/usr/bin/env bash
set -euo pipefail

# Preflight SSH redundancy check
# Verifies OpenSSH connectivity and optionally Tailscale SSH

if [ $# -eq 0 ]; then
    echo "Usage: $0 <hostname|IP>"
    echo "Example: $0 pi-a.local"
    exit 1
fi

host="$1"

echo "=== SSH Redundancy Check for $host ==="

# Test OpenSSH connectivity
echo -n "Testing OpenSSH... "
if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$host" -- 'true' 2>/dev/null; then
    echo "✓ OK"
    openssh_ok=true
else
    echo "✗ FAILED"
    openssh_ok=false
fi

# Test Tailscale SSH (optional, non-fatal if fails)
echo -n "Testing Tailscale SSH... "
if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$host" -- 'tailscale status >/dev/null 2>&1' 2>/dev/null; then
    echo "✓ OK"
    tailscale_ok=true
else
    echo "⚠ Not available (non-critical)"
    tailscale_ok=false
fi

echo ""
echo "=== Summary ==="
echo "OpenSSH: $([ "$openssh_ok" = true ] && echo "✓ Working" || echo "✗ Failed")"
echo "Tailscale: $([ "$tailscale_ok" = true ] && echo "✓ Working" || echo "⚠ Not available")"

# At least one SSH method must work
if [ "$openssh_ok" = true ] || [ "$tailscale_ok" = true ]; then
    echo ""
    echo "✓ SSH redundancy check PASSED"
    exit 0
else
    echo ""
    echo "✗ SSH redundancy check FAILED - No SSH connectivity available"
    exit 1
fi