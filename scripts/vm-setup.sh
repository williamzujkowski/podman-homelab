#!/usr/bin/env bash
set -euo pipefail

# VM setup script for Multipass staging environment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
VMS=("vm-a" "vm-b" "vm-c")
VM_CPUS=${VM_CPUS:-2}
VM_MEMORY=${VM_MEMORY:-4G}
VM_DISK=${VM_DISK:-30G}
UBUNTU_VERSION=${UBUNTU_VERSION:-24.04}

echo "=== Multipass VM Setup for Homelab Staging ==="
echo "CPUs: $VM_CPUS, Memory: $VM_MEMORY, Disk: $VM_DISK"
echo ""

# Check if multipass is installed
if ! command -v multipass &> /dev/null; then
    echo "ERROR: Multipass not found. Please install it first:"
    echo "  Ubuntu/Debian: sudo snap install multipass"
    echo "  MacOS: brew install --cask multipass"
    exit 1
fi

# Function to create VM
create_vm() {
    local vm_name=$1
    echo "Creating VM: $vm_name"
    
    if multipass list | grep -q "^$vm_name "; then
        echo "  VM $vm_name already exists, skipping..."
        return 0
    fi
    
    multipass launch "$UBUNTU_VERSION" \
        --name "$vm_name" \
        --cpus "$VM_CPUS" \
        --memory "$VM_MEMORY" \
        --disk "$VM_DISK" \
        --cloud-init "${PROJECT_ROOT}/cloud-init/user-data.yml" 2>/dev/null || {
            # Fallback without cloud-init if file doesn't exist
            multipass launch "$UBUNTU_VERSION" \
                --name "$vm_name" \
                --cpus "$VM_CPUS" \
                --memory "$VM_MEMORY" \
                --disk "$VM_DISK"
        }
    
    echo "  VM $vm_name created successfully"
}

# Function to get VM info
get_vm_info() {
    local vm_name=$1
    multipass info "$vm_name" --format json 2>/dev/null | jq -r '.info["'$vm_name'"].ipv4[0] // "N/A"'
}

# Create VMs
echo "Creating VMs..."
for vm in "${VMS[@]}"; do
    create_vm "$vm"
done

echo ""
echo "Waiting for VMs to be ready..."
sleep 10

# Display VM information
echo ""
echo "=== VM Information ==="
for vm in "${VMS[@]}"; do
    ip=$(get_vm_info "$vm")
    status=$(multipass list | grep "^$vm " | awk '{print $2}')
    echo "$vm: IP=$ip, Status=$status"
done

echo ""
echo "=== SSH Configuration ==="
echo "Add the following to your ~/.ssh/config:"
echo ""
for vm in "${VMS[@]}"; do
    ip=$(get_vm_info "$vm")
    cat <<EOF
Host $vm $vm.local
    HostName $ip
    User ubuntu
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

EOF
done

echo "=== Next Steps ==="
echo "1. Update ansible/inventories/local/hosts.yml with the VM IP addresses"
echo "2. Run: ansible -i ansible/inventories/local/hosts.yml all -m ping"
echo "3. Run: ansible-playbook -i ansible/inventories/local/hosts.yml ansible/playbooks/00-bootstrap.yml"
echo ""
echo "VM setup complete!"