#!/bin/bash

# Import a single dashboard
DASHBOARD_ID="$1"
DASHBOARD_TITLE="$2"

GRAFANA_URL="http://192.168.1.12:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="JKmUmdS2cpmJeBY"

if [[ -z "$DASHBOARD_ID" ]]; then
    echo "Usage: $0 <dashboard_id> [title]"
    exit 1
fi

echo "Fetching dashboard ${DASHBOARD_ID}..."

# Download dashboard
curl -s "https://grafana.com/api/dashboards/${DASHBOARD_ID}/revisions/latest/download" -o "/tmp/dashboard-${DASHBOARD_ID}.json"

if [[ ! -s "/tmp/dashboard-${DASHBOARD_ID}.json" ]]; then
    echo "Failed to download dashboard"
    exit 1
fi

echo "Creating import payload..."

# Create the import request
cat > "/tmp/import-${DASHBOARD_ID}.json" << 'EOF'
{
  "dashboard": 
EOF

cat "/tmp/dashboard-${DASHBOARD_ID}.json" >> "/tmp/import-${DASHBOARD_ID}.json"

cat >> "/tmp/import-${DASHBOARD_ID}.json" << 'EOF'
,
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

echo "Importing dashboard..."

# Import dashboard
response=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
               -H "Content-Type: application/json" \
               -X POST \
               "${GRAFANA_URL}/api/dashboards/import" \
               -d "@/tmp/import-${DASHBOARD_ID}.json")

echo "Response: $response"

# Check if import was successful
if echo "$response" | jq -e '.status' >/dev/null 2>&1; then
    status=$(echo "$response" | jq -r '.status')
    if [[ "$status" == "success" ]]; then
        echo "✅ Dashboard imported successfully!"
        dashboard_url=$(echo "$response" | jq -r '.importedUrl // empty')
        if [[ -n "$dashboard_url" ]]; then
            echo "🔗 Dashboard URL: ${GRAFANA_URL}${dashboard_url}"
        fi
    else
        echo "❌ Import failed: $(echo "$response" | jq -r '.message // .error // "Unknown error"')"
    fi
else
    echo "❌ Invalid response or import failed"
fi

# Cleanup
rm -f "/tmp/dashboard-${DASHBOARD_ID}.json" "/tmp/import-${DASHBOARD_ID}.json"