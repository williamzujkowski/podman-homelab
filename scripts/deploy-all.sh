#!/usr/bin/env bash
set -euo pipefail

# Complete deployment script for homelab infrastructure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
INVENTORY="${INVENTORY:-ansible/inventories/local/hosts.yml}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/homelab_key}"
ANSIBLE_PASS="${ANSIBLE_PASS:-ubuntu}"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to run playbook
run_playbook() {
    local playbook=$1
    local description=$2
    
    print_status "Running: $description"
    
    if ansible-playbook -i "$INVENTORY" "$playbook" \
        --private-key "$SSH_KEY" \
        -e "ansible_become_pass=$ANSIBLE_PASS"; then
        print_status "✓ $description completed successfully"
        return 0
    else
        print_error "✗ $description failed"
        return 1
    fi
}

# Check prerequisites
print_status "Checking prerequisites..."

if [ ! -f "$SSH_KEY" ]; then
    print_error "SSH key not found: $SSH_KEY"
    exit 1
fi

if ! command -v ansible &> /dev/null; then
    print_error "Ansible not installed"
    exit 1
fi

# Test connectivity
print_status "Testing VM connectivity..."
if ! ansible all -i "$INVENTORY" -m ping --private-key "$SSH_KEY" &>/dev/null; then
    print_warning "Some VMs are not reachable. Continuing anyway..."
fi

# Deployment sequence
PLAYBOOKS=(
    "ansible/playbooks/00-bootstrap.yml:Bootstrap VMs"
    "ansible/playbooks/10-base.yml:Base configuration"
    "ansible/playbooks/20-podman.yml:Podman runtime"
    "ansible/playbooks/30-observability.yml:Observability stack"
    "ansible/playbooks/40-ingress.yml:Ingress controller"
)

# Run deployments
for playbook_info in "${PLAYBOOKS[@]}"; do
    IFS=':' read -r playbook description <<< "$playbook_info"
    
    if [ -f "$playbook" ]; then
        run_playbook "$playbook" "$description" || {
            print_error "Deployment failed at: $description"
            exit 1
        }
    else
        print_warning "Playbook not found: $playbook"
    fi
done

# Verification
print_status "Running service verification..."
if [ -f scripts/verify_services.sh ]; then
    ./scripts/verify_services.sh 10.14.185.35 10.14.185.67 10.14.185.213 || {
        print_warning "Some services may not be healthy yet"
    }
fi

print_status "========================"
print_status "Deployment Complete!"
print_status "========================"
print_status ""
print_status "Access services at:"
print_status "  Grafana: http://10.14.185.35:3000 (admin/admin)"
print_status "  Prometheus: http://10.14.185.35:9090"
print_status "  Ingress: http://10.14.185.67"