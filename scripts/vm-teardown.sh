#!/usr/bin/env bash
set -euo pipefail

# VM teardown script for Multipass staging environment

VMS=("vm-a" "vm-b" "vm-c")

echo "=== Multipass VM Teardown ==="
echo "This will delete the following VMs: ${VMS[*]}"
echo ""

read -p "Are you sure you want to delete these VMs? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Teardown cancelled."
    exit 0
fi

for vm in "${VMS[@]}"; do
    if multipass list | grep -q "^$vm "; then
        echo "Stopping $vm..."
        multipass stop "$vm" 2>/dev/null || true
        
        echo "Deleting $vm..."
        multipass delete "$vm"
    else
        echo "$vm not found, skipping..."
    fi
done

echo ""
echo "Purging deleted VMs..."
multipass purge

echo ""
echo "VM teardown complete!"