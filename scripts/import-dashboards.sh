#!/bin/bash

# Import essential Grafana dashboards
set -euo pipefail

GRAFANA_URL="http://192.168.1.12:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="JKmUmdS2cpmJeBY"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to import dashboard
import_dashboard() {
    local dashboard_id="$1"
    local dashboard_title="$2"
    
    print_status "Importing dashboard: $dashboard_title (ID: $dashboard_id)..."
    
    # Fetch dashboard JSON
    local dashboard_json=$(curl -s "https://grafana.com/api/dashboards/${dashboard_id}/revisions/latest/download")
    
    if [[ -z "$dashboard_json" ]] || [[ "$dashboard_json" == *"error"* ]]; then
        print_error "Failed to fetch dashboard $dashboard_id"
        return 1
    fi
    
    # Create import payload
    local import_payload=$(jq -n \
        --argjson dashboard "$dashboard_json" \
        '{
            dashboard: $dashboard,
            overwrite: true,
            inputs: [
                {
                    name: "DS_PROMETHEUS",
                    type: "datasource",
                    pluginId: "prometheus",
                    value: "Prometheus"
                }
            ],
            folderId: 0
        }')
    
    local response=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
                          -H "Content-Type: application/json" \
                          -X POST \
                          "${GRAFANA_URL}/api/dashboards/import" \
                          -d "${import_payload}")
    
    if echo "$response" | jq -e '.status == "success"' >/dev/null 2>&1; then
        print_success "Dashboard '$dashboard_title' imported successfully"
        local dashboard_url=$(echo "$response" | jq -r '.importedUrl // empty')
        if [[ -n "$dashboard_url" ]]; then
            print_status "Dashboard URL: ${GRAFANA_URL}${dashboard_url}"
        fi
        return 0
    else
        local error_msg=$(echo "$response" | jq -r '.message // .error // "Unknown error"')
        print_error "Failed to import '$dashboard_title': $error_msg"
        return 1
    fi
}

# Main execution
main() {
    print_status "Starting dashboard import..."
    echo
    
    # Essential dashboards to import
    import_dashboard "1860" "Node Exporter Full"
    echo
    
    import_dashboard "3662" "Prometheus 2.0 Stats"
    echo
    
    import_dashboard "11074" "Node Exporter for Prometheus Dashboard"
    echo
    
    import_dashboard "8919" "1 Node Exporter Dashboard"
    echo
    
    print_success "Dashboard import completed!"
    print_status "Access Grafana at: $GRAFANA_URL"
}

main "$@"