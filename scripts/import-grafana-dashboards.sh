#!/usr/bin/env bash
# Importa dashboards JSON via Grafana API
set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-admin123}"
DASHBOARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/k8s/grafana/dashboards"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()  { echo -e "${GREEN}[OK]${NC}   $*"; }

log "Importando dashboards para ${GRAFANA_URL}..."

for json_file in "${DASHBOARDS_DIR}"/*.json; do
  dashboard_name=$(basename "$json_file" .json)
  log "Importando: ${dashboard_name}..."

  payload=$(python3 -c "
import json, sys
with open('${json_file}') as f:
    d = json.load(f)
print(json.dumps({'dashboard': d, 'overwrite': True, 'folderId': 0}))
")

  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${GRAFANA_URL}/api/dashboards/import")

  if [ "$STATUS" = "200" ]; then
    ok "${dashboard_name} importado (HTTP ${STATUS})"
  else
    echo "  Aviso: ${dashboard_name} retornou HTTP ${STATUS}"
  fi
done

ok "Dashboards importados. Acesse: ${GRAFANA_URL}"
