#!/bin/bash
# Import Grafana dashboards to the homelab monitoring system
# This script copies dashboard files and runs the Ansible playbook to import them

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DASHBOARDS_DIR="$REPO_ROOT/grafana-dashboards"
ANSIBLE_DIR="$REPO_ROOT/ansible"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Grafana connection details
GRAFANA_URL="${GRAFANA_URL:-http://192.168.1.12:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin}"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_requirements() {
    log_info "Checking requirements..."
    
    # Check if dashboard files exist
    if [[ ! -d "$DASHBOARDS_DIR" ]]; then
        log_error "Dashboard directory not found: $DASHBOARDS_DIR"
        exit 1
    fi
    
    local dashboard_count
    dashboard_count=$(find "$DASHBOARDS_DIR" -name "*.json" | wc -l)
    if [[ $dashboard_count -eq 0 ]]; then
        log_error "No dashboard JSON files found in $DASHBOARDS_DIR"
        exit 1
    fi
    
    log_info "Found $dashboard_count dashboard files"
    
    # Check if Ansible is available
    if ! command -v ansible-playbook &> /dev/null; then
        log_error "ansible-playbook not found. Please install Ansible."
        exit 1
    fi
    
    # Check if Grafana is accessible
    if command -v curl &> /dev/null; then
        if curl -s "$GRAFANA_URL/api/health" &> /dev/null; then
            log_success "Grafana is accessible at $GRAFANA_URL"
        else
            log_warning "Cannot reach Grafana at $GRAFANA_URL (may be expected if running remotely)"
        fi
    fi
}

list_dashboards() {
    log_info "Available dashboards:"
    find "$DASHBOARDS_DIR" -name "*.json" -exec basename {} \; | sort | while read -r dashboard; do
        echo "  - $dashboard"
    done
}

import_via_ansible() {
    log_info "Importing dashboards via Ansible playbook..."
    
    cd "$ANSIBLE_DIR"
    
    if [[ -f "playbooks/60-grafana-dashboards.yml" ]]; then
        ansible-playbook -i inventories/prod/hosts.yml \
            playbooks/60-grafana-dashboards.yml \
            --limit monitoring_nodes \
            --extra-vars "grafana_admin_password=$GRAFANA_PASSWORD"
        
        if [[ $? -eq 0 ]]; then
            log_success "Dashboards imported successfully via Ansible"
        else
            log_error "Ansible playbook failed"
            exit 1
        fi
    else
        log_error "Ansible playbook not found: playbooks/60-grafana-dashboards.yml"
        exit 1
    fi
}

import_via_api() {
    log_info "Importing dashboards directly via Grafana API..."
    
    if ! command -v curl &> /dev/null; then
        log_error "curl not found. Please install curl for API import."
        exit 1
    fi
    
    local folder_mapping
    declare -A folder_mapping
    folder_mapping["cluster-overview.json"]="Homelab"
    folder_mapping["node-details.json"]="Homelab" 
    folder_mapping["service-health.json"]="Homelab"
    folder_mapping["authentik-monitoring.json"]="Security"
    folder_mapping["alert-dashboard.json"]="Alerts"
    
    # Create folders first
    for folder in "Homelab" "Security" "Alerts"; do
        log_info "Creating folder: $folder"
        curl -s -X POST \
            -H "Content-Type: application/json" \
            -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
            -d "{\"title\":\"$folder\",\"uid\":\"$(echo "$folder" | tr '[:upper:]' '[:lower:]')\"}" \
            "$GRAFANA_URL/api/folders" > /dev/null || true  # Ignore if folder exists
    done
    
    # Import dashboards
    for dashboard_file in "$DASHBOARDS_DIR"/*.json; do
        local filename
        filename=$(basename "$dashboard_file")
        log_info "Importing dashboard: $filename"
        
        local response
        response=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
            -d @"$dashboard_file" \
            "$GRAFANA_URL/api/dashboards/db")
        
        if echo "$response" | grep -q '"status":"success"'; then
            log_success "Successfully imported: $filename"
        else
            log_error "Failed to import: $filename"
            echo "$response" | jq '.' 2>/dev/null || echo "$response"
        fi
    done
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Import Grafana dashboards to the homelab monitoring system.

OPTIONS:
    -h, --help          Show this help message
    -l, --list          List available dashboards
    -m, --method METHOD Import method: 'ansible' (default) or 'api'
    --grafana-url URL   Grafana URL (default: $GRAFANA_URL)
    --grafana-user USER Grafana username (default: $GRAFANA_USER)
    --grafana-password PWD Grafana password (default: from env or 'admin')

EXAMPLES:
    # Import using Ansible (recommended)
    $0

    # Import directly via API
    $0 --method api

    # List available dashboards
    $0 --list

    # Import to custom Grafana instance
    $0 --grafana-url http://grafana.example.com:3000 --grafana-user admin --grafana-password secret

ENVIRONMENT VARIABLES:
    GRAFANA_URL         Override default Grafana URL
    GRAFANA_USER        Override default Grafana username
    GRAFANA_PASSWORD    Override default Grafana password

EOF
}

main() {
    local import_method="ansible"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -l|--list)
                list_dashboards
                exit 0
                ;;
            -m|--method)
                import_method="$2"
                shift 2
                ;;
            --grafana-url)
                GRAFANA_URL="$2"
                shift 2
                ;;
            --grafana-user)
                GRAFANA_USER="$2"
                shift 2
                ;;
            --grafana-password)
                GRAFANA_PASSWORD="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log_info "Starting Grafana dashboard import..."
    log_info "Method: $import_method"
    log_info "Grafana URL: $GRAFANA_URL"
    
    check_requirements
    
    case $import_method in
        ansible)
            import_via_ansible
            ;;
        api)
            import_via_api
            ;;
        *)
            log_error "Invalid import method: $import_method"
            log_error "Valid methods: ansible, api"
            exit 1
            ;;
    esac
    
    log_success "Dashboard import completed!"
    log_info "Access your dashboards at: $GRAFANA_URL/dashboards"
}

main "$@"