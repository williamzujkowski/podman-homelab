#!/usr/bin/env bash
set -euo pipefail

# Preflight time synchronization check
# Ensures chrony is synchronized with acceptable drift and stratum
# Requirements: drift < 100ms, stratum <= 3

echo "=== Time Synchronization Check ==="

# Check if chrony is installed
if ! command -v chronyc &> /dev/null; then
    echo "ERROR: chronyc not found. Install chrony first."
    exit 1
fi

# Get tracking info
chronyc -n tracking

# Extract offset and stratum
offset=$(chronyc tracking | awk '/Last offset/ {print ($4<0?-1*$4:$4)}')
stratum=$(chronyc tracking | awk '/Stratum/ {print $3}')

echo ""
echo "Offset: ${offset}s"
echo "Stratum: ${stratum}"

# Convert offset to milliseconds for comparison
offset_ms=$(echo "$offset * 1000" | bc -l 2>/dev/null || echo "1000")

# Check requirements
if (( $(echo "$offset_ms < 100" | bc -l) )) && [ "$stratum" -le 3 ]; then
    echo "✓ Time sync OK (drift < 100ms, stratum ≤ 3)"
    exit 0
else
    echo "✗ Time sync FAILED (drift=${offset_ms}ms, stratum=${stratum})"
    echo "  Requirements: drift < 100ms, stratum ≤ 3"
    exit 1
fi