#!/usr/bin/env bash
# =============================================================================
# integration-test.sh — Testes de Integração com docker-compose
# Uso: bash scripts/integration-test.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_ROOT}/.env.docker"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yaml"
APP_PORT=19000
POSTGRES_PORT=19432
TIMEOUT=60

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[PASS]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; }

cleanup() {
  log "Derrubando stack de integração..."
  PORT=$APP_PORT POSTGRES_PORT=$POSTGRES_PORT \
    docker compose \
      --env-file "$ENV_FILE" \
      -f "$COMPOSE_FILE" \
      --project-name et-integration \
      down --volumes --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT

cd "$PROJECT_ROOT"

echo -e "\n${BLUE}══════════════════════════════════════════${NC}"
echo -e "${BLUE}  TESTES DE INTEGRAÇÃO — ENCONTROS TECH${NC}"
echo -e "${BLUE}══════════════════════════════════════════${NC}\n"

# Sobe stack
log "Subindo stack de integração (portas: app=${APP_PORT}, db=${POSTGRES_PORT})..."
PORT=$APP_PORT POSTGRES_PORT=$POSTGRES_PORT \
  docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    --project-name et-integration \
    up -d --build 2>/dev/null

# Aguarda services
log "Aguardando postgres (et-postgres) ficar healthy..."
elapsed=0
until [ "$(docker inspect --format='{{.State.Health.Status}}' et-postgres 2>/dev/null)" = "healthy" ]; do
  [ "$elapsed" -ge "$TIMEOUT" ] && { fail "Timeout aguardando postgres"; exit 1; }
  sleep 2; elapsed=$((elapsed + 2))
done
ok "postgres healthy (${elapsed}s)"

log "Aguardando app (et-app) ficar healthy..."
elapsed=0
until [ "$(docker inspect --format='{{.State.Health.Status}}' et-app 2>/dev/null)" = "healthy" ]; do
  [ "$elapsed" -ge "$TIMEOUT" ] && { fail "Timeout aguardando app"; exit 1; }
  sleep 2; elapsed=$((elapsed + 2))
done
ok "app healthy (${elapsed}s)"

# Executa testes de integração dentro do container
log "Executando testes de integração..."
echo ""

docker exec et-app sh -c "
  pip install pytest pytest-asyncio httpx --quiet 2>/dev/null
  DATABASE_URL=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB} \
  pytest /app/tests/test_integration.py \
    -v \
    --tb=short \
    -q \
    2>&1
" && EXIT_CODE=0 || EXIT_CODE=1

echo ""
if [ "$EXIT_CODE" -eq 0 ]; then
  ok "Todos os testes de integração passaram!"
else
  fail "Alguns testes falharam — verifique o output acima."
fi

exit "$EXIT_CODE"
