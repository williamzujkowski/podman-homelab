#!/bin/bash

# Grafana configuration script
# Purpose: Configure Prometheus data source and import dashboards

set -euo pipefail

# Configuration
GRAFANA_URL="http://192.168.1.12:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="JKmUmdS2cpmJeBY"
PROMETHEUS_URL="http://localhost:9090"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if data source exists
check_data_source() {
    local name="$1"
    curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
         "${GRAFANA_URL}/api/datasources/name/${name}" \
         -w "%{http_code}" -o /dev/null
}

# Function to create Prometheus data source
create_prometheus_datasource() {
    print_status "Creating Prometheus data source..."
    
    local datasource_json=$(cat <<EOF
{
  "name": "Prometheus",
  "type": "prometheus",
  "url": "${PROMETHEUS_URL}",
  "access": "proxy",
  "isDefault": true,
  "basicAuth": false,
  "jsonData": {
    "httpMethod": "POST",
    "manageAlerts": true,
    "alertmanagerUid": "",
    "prometheusType": "Prometheus",
    "prometheusVersion": "2.48.0",
    "cacheLevel": "High",
    "disableRecordingRules": false,
    "incrementalQueryOverlapWindow": "10m",
    "exemplarTraceIdDestinations": []
  }
}
EOF
)

    local response=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
                          -H "Content-Type: application/json" \
                          -X POST \
                          "${GRAFANA_URL}/api/datasources" \
                          -d "${datasource_json}" \
                          -w "%{http_code}")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [[ "$http_code" == "200" ]]; then
        print_success "Prometheus data source created successfully"
        return 0
    elif [[ "$http_code" == "409" ]]; then
        print_warning "Prometheus data source already exists"
        return 0
    else
        print_error "Failed to create Prometheus data source (HTTP $http_code): $body"
        return 1
    fi
}

# Function to import dashboard
import_dashboard() {
    local dashboard_id="$1"
    local dashboard_title="$2"
    
    print_status "Importing dashboard: $dashboard_title (ID: $dashboard_id)..."
    
    # First, fetch the dashboard from grafana.com
    local dashboard_json=$(curl -s "https://grafana.com/api/dashboards/${dashboard_id}/revisions/latest/download")
    
    if [[ -z "$dashboard_json" ]] || [[ "$dashboard_json" == *"error"* ]]; then
        print_error "Failed to fetch dashboard $dashboard_id from grafana.com"
        return 1
    fi
    
    # Prepare the import payload
    local import_payload=$(cat <<EOF
{
  "dashboard": $dashboard_json,
  "overwrite": true,
  "inputs": [
    {
      "name": "DS_PROMETHEUS",
      "type": "datasource",
      "pluginId": "prometheus",
      "value": "Prometheus"
    }
  ],
  "folderId": 0
}
EOF
)
    
    local response=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
                          -H "Content-Type: application/json" \
                          -X POST \
                          "${GRAFANA_URL}/api/dashboards/import" \
                          -d "${import_payload}" \
                          -w "%{http_code}")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [[ "$http_code" == "200" ]]; then
        print_success "Dashboard '$dashboard_title' imported successfully"
        # Extract dashboard URL from response
        local dashboard_url=$(echo "$body" | jq -r '.importedUrl // empty')
        if [[ -n "$dashboard_url" ]]; then
            print_status "Dashboard URL: ${GRAFANA_URL}${dashboard_url}"
        fi
        return 0
    else
        print_error "Failed to import dashboard '$dashboard_title' (HTTP $http_code): $body"
        return 1
    fi
}

# Function to test data source
test_datasource() {
    print_status "Testing Prometheus data source..."
    
    local response=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
                          -H "Content-Type: application/json" \
                          -X POST \
                          "${GRAFANA_URL}/api/datasources/proxy/1/api/v1/query" \
                          -d "query=up" \
                          -w "%{http_code}")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [[ "$http_code" == "200" ]]; then
        local targets_up=$(echo "$body" | jq -r '.data.result | length')
        print_success "Data source test successful - $targets_up targets found"
        return 0
    else
        print_error "Data source test failed (HTTP $http_code): $body"
        return 1
    fi
}

# Function to query and display node metrics
show_node_metrics() {
    print_status "Querying node metrics..."
    
    # Query for node instances
    local response=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
                          -H "Content-Type: application/json" \
                          -X POST \
                          "${GRAFANA_URL}/api/datasources/proxy/1/api/v1/query" \
                          -d "query=up{job=\"node\"}")
    
    if [[ $? -eq 0 ]] && [[ "$response" == *"success"* ]]; then
        echo
        print_success "Node targets found:"
        echo "$response" | jq -r '.data.result[] | "  - " + .metric.instance + " (job: " + .metric.job + ", status: " + .value[1] + ")"'
    fi
    
    # Query for CPU usage
    print_status "Sample CPU usage query..."
    local cpu_response=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
                              -H "Content-Type: application/json" \
                              -X POST \
                              "${GRAFANA_URL}/api/datasources/proxy/1/api/v1/query" \
                              -d "query=100 - (avg by(instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)")
    
    if [[ $? -eq 0 ]] && [[ "$cpu_response" == *"success"* ]]; then
        echo
        print_success "Current CPU usage by instance:"
        echo "$cpu_response" | jq -r '.data.result[] | "  - " + .metric.instance + ": " + (.value[1] | tonumber | . * 100 | round / 100 | tostring) + "%"'
    fi
}

# Main execution
main() {
    print_status "Starting Grafana configuration..."
    echo
    
    # Check Grafana connectivity
    print_status "Checking Grafana connectivity..."
    if ! curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" "${GRAFANA_URL}/api/health" >/dev/null; then
        print_error "Cannot connect to Grafana at $GRAFANA_URL"
        exit 1
    fi
    print_success "Grafana is accessible"
    echo
    
    # Create Prometheus data source
    create_prometheus_datasource
    echo
    
    # Test the data source
    test_datasource
    echo
    
    # Import essential dashboards
    print_status "Importing essential dashboards..."
    echo
    
    import_dashboard "1860" "Node Exporter Full"
    echo
    
    import_dashboard "3662" "Prometheus 2.0 Stats"
    echo
    
    import_dashboard "11074" "Node Exporter for Prometheus Dashboard"
    echo
    
    import_dashboard "8919" "1 Node Exporter Dashboard 22/04/13"
    echo
    
    # Show some sample metrics
    show_node_metrics
    echo
    
    print_success "Grafana configuration completed!"
    print_status "You can access Grafana at: $GRAFANA_URL"
    print_status "Username: $GRAFANA_USER"
    print_status "Password: $GRAFANA_PASS"
}

# Run main function
main "$@"