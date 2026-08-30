#!/usr/bin/env bash
# =============================================================================
# test-local.sh — Validação completa da Fase 1
# Uso: bash scripts/test-local.sh
# Requer: docker, docker compose, curl
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuração
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
IMAGE_NAME="encontros-tech-api"
IMAGE_TAG="local-test"
MAX_SIZE_MB=300
APP_PORT=18000          # porta isolada para o teste (evita conflito)
POSTGRES_PORT=15437     # porta isolada para postgres no teste
ENV_FILE="${PROJECT_ROOT}/.env.docker"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yaml"
TIMEOUT=60              # segundos para aguardar containers ficarem healthy

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0

# -----------------------------------------------------------------------------
# Funções utilitárias
# -----------------------------------------------------------------------------
log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[PASS]${NC}  $*"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; FAIL=$((FAIL + 1)); }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }

separator() { echo -e "\n${BLUE}══════════════════════════════════════════════════${NC}"; }

cleanup() {
  log "Limpando recursos do teste..."
  docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    --project-name et-test \
    down --volumes --remove-orphans 2>/dev/null || true
  docker rmi "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || true
  log "Limpeza concluída."
}

wait_healthy() {
  local container="$1"
  local elapsed=0
  log "Aguardando '${container}' ficar healthy (timeout: ${TIMEOUT}s)..."
  until [ "$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null)" = "healthy" ]; do
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
      fail "Timeout: '${container}' não ficou healthy em ${TIMEOUT}s"
      docker logs "$container" 2>&1 | tail -20
      return 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  ok "'${container}' está healthy (${elapsed}s)"
}

# -----------------------------------------------------------------------------
# Trap para garantir limpeza em caso de erro
# -----------------------------------------------------------------------------
trap cleanup EXIT

cd "$PROJECT_ROOT"

separator
echo -e "${BLUE}  ENCONTROS TECH — VALIDAÇÃO FASE 1${NC}"
echo -e "${BLUE}  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
separator

# -----------------------------------------------------------------------------
# 1. Verificar pré-requisitos
# -----------------------------------------------------------------------------
log "Verificando pré-requisitos..."

if ! command -v docker &>/dev/null; then
  fail "docker não encontrado"; exit 1
fi
ok "docker $(docker --version | awk '{print $3}' | tr -d ',')"

if ! docker compose version &>/dev/null; then
  fail "docker compose não encontrado"; exit 1
fi
ok "docker compose $(docker compose version | awk '{print $NF}')"

if ! command -v curl &>/dev/null; then
  fail "curl não encontrado"; exit 1
fi
ok "curl disponível"

if [ ! -f "$ENV_FILE" ]; then
  warn ".env.docker não encontrado — usando .env.docker.example"
  cp "${PROJECT_ROOT}/.env.docker.example" "$ENV_FILE"
fi
ok ".env.docker presente"

# -----------------------------------------------------------------------------
# 2. Verificar arquivos da Fase 1
# -----------------------------------------------------------------------------
separator
log "Verificando arquivos da Fase 1..."

FILES=(
  "app/main.py"
  "app/requirements.txt"
  "app/requirements-dev.txt"
  "app/.env.example"
  "app/tests/__init__.py"
  "app/tests/test_api.py"
  "app/pytest.ini"
  "docker/Dockerfile"
  "docker/.dockerignore"
  "docker-compose.yaml"
  ".env.docker.example"
)

for f in "${FILES[@]}"; do
  if [ -f "${PROJECT_ROOT}/${f}" ]; then
    ok "${f}"
  else
    fail "${f} — NÃO ENCONTRADO"
  fi
done

# -----------------------------------------------------------------------------
# 3. Build da imagem Docker
# -----------------------------------------------------------------------------
separator
log "Fazendo build da imagem Docker (${IMAGE_NAME}:${IMAGE_TAG})..."

if docker build \
    --file docker/Dockerfile \
    --tag "${IMAGE_NAME}:${IMAGE_TAG}" \
    --quiet \
    . > /dev/null 2>&1; then
  ok "Build concluído: ${IMAGE_NAME}:${IMAGE_TAG}"
else
  fail "Build falhou"
  docker build --file docker/Dockerfile --tag "${IMAGE_NAME}:${IMAGE_TAG}" . 2>&1 | tail -20
  exit 1
fi

# -----------------------------------------------------------------------------
# 4. Verificar tamanho da imagem
# -----------------------------------------------------------------------------
separator
log "Verificando tamanho da imagem..."

SIZE_RAW=$(docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" --format='{{.VirtualSize}}')
SIZE_MB=$(python3 -c "print(round($SIZE_RAW / 1024 / 1024, 1))")
SIZE_INT=$(python3 -c "print(int($SIZE_RAW / 1024 / 1024))")

log "Tamanho da imagem: ${SIZE_MB} MB (limite: ${MAX_SIZE_MB} MB)"

if [ "$SIZE_INT" -lt "$MAX_SIZE_MB" ]; then
  ok "Tamanho OK: ${SIZE_MB} MB < ${MAX_SIZE_MB} MB"
else
  fail "Imagem muito grande: ${SIZE_MB} MB >= ${MAX_SIZE_MB} MB"
fi

# -----------------------------------------------------------------------------
# 5. Subir docker-compose com portas de teste isoladas
# -----------------------------------------------------------------------------
separator
log "Iniciando stack docker-compose (portas de teste: app=${APP_PORT}, db=${POSTGRES_PORT})..."

PORT=$APP_PORT POSTGRES_PORT=$POSTGRES_PORT \
  docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    --project-name et-test \
    up -d --build 2>/dev/null

# -----------------------------------------------------------------------------
# 6. Aguardar postgres ficar healthy
# -----------------------------------------------------------------------------
separator
log "Aguardando serviços ficarem healthy..."

wait_healthy "et-postgres" || { fail "postgres não iniciou"; exit 1; }
wait_healthy "et-app"      || { fail "app não iniciou"; exit 1; }

# -----------------------------------------------------------------------------
# 7. Testes de endpoints
# -----------------------------------------------------------------------------
separator
log "Testando endpoints da API na porta ${APP_PORT}..."

BASE_URL="http://localhost:${APP_PORT}"

# GET /health
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/health")
if [ "$HEALTH_STATUS" = "200" ]; then
  ok "GET /health → HTTP ${HEALTH_STATUS}"
  HEALTH_BODY=$(curl -sf "${BASE_URL}/health")
  STATUS_VAL=$(echo "$HEALTH_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])" 2>/dev/null || echo "")
  if [ "$STATUS_VAL" = "healthy" ]; then
    ok "GET /health → status=healthy"
  else
    fail "GET /health → status esperado 'healthy', recebido '${STATUS_VAL}'"
  fi
else
  fail "GET /health → HTTP ${HEALTH_STATUS} (esperado 200)"
fi

# GET /ready
READY_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/ready")
if [ "$READY_STATUS" = "200" ]; then
  ok "GET /ready → HTTP ${READY_STATUS}"
else
  fail "GET /ready → HTTP ${READY_STATUS} (esperado 200)"
fi

# GET /metrics
METRICS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/metrics")
if [ "$METRICS_STATUS" = "200" ]; then
  ok "GET /metrics → HTTP ${METRICS_STATUS}"
  METRICS_BODY=$(curl -sf "${BASE_URL}/metrics")
  if echo "$METRICS_BODY" | grep -q "http_requests_total"; then
    ok "GET /metrics → contém 'http_requests_total'"
  else
    fail "GET /metrics → métrica 'http_requests_total' não encontrada"
  fi
else
  fail "GET /metrics → HTTP ${METRICS_STATUS} (esperado 200)"
fi

# GET /api/v2/eventos
EVENTOS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/v2/eventos")
if [ "$EVENTOS_STATUS" = "200" ]; then
  ok "GET /api/v2/eventos → HTTP ${EVENTOS_STATUS}"
  TOTAL=$(curl -sf "${BASE_URL}/api/v2/eventos" | python3 -c "import sys,json; print(json.load(sys.stdin)['total'])" 2>/dev/null || echo "0")
  if [ "$TOTAL" -gt 0 ]; then
    ok "GET /api/v2/eventos → total=${TOTAL} eventos retornados"
  else
    fail "GET /api/v2/eventos → nenhum evento retornado"
  fi
else
  fail "GET /api/v2/eventos → HTTP ${EVENTOS_STATUS} (esperado 200)"
fi

# GET /api/v2/eventos/1
EVENTO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/v2/eventos/1")
if [ "$EVENTO_STATUS" = "200" ]; then
  ok "GET /api/v2/eventos/1 → HTTP ${EVENTO_STATUS}"
else
  fail "GET /api/v2/eventos/1 → HTTP ${EVENTO_STATUS} (esperado 200)"
fi

# GET /api/v2/eventos/9999 (deve retornar 404)
NOT_FOUND=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/v2/eventos/9999")
if [ "$NOT_FOUND" = "404" ]; then
  ok "GET /api/v2/eventos/9999 → HTTP ${NOT_FOUND} (404 esperado)"
else
  fail "GET /api/v2/eventos/9999 → HTTP ${NOT_FOUND} (esperado 404)"
fi

# -----------------------------------------------------------------------------
# 8. Verificar usuário não-root
# -----------------------------------------------------------------------------
separator
log "Verificando segurança do container..."

CONTAINER_USER=$(docker exec et-app whoami 2>/dev/null || echo "erro")
if [ "$CONTAINER_USER" = "appuser" ]; then
  ok "Container rodando como usuário não-root: ${CONTAINER_USER}"
else
  fail "Container não está rodando como 'appuser' (encontrado: ${CONTAINER_USER})"
fi

# -----------------------------------------------------------------------------
# 9. Verificar rede
# -----------------------------------------------------------------------------
log "Verificando rede tech-network..."
if docker network inspect tech-network &>/dev/null; then
  CONTAINERS_IN_NETWORK=$(docker network inspect tech-network \
    --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)
  ok "Rede 'tech-network' existe — containers: ${CONTAINERS_IN_NETWORK}"
else
  fail "Rede 'tech-network' não encontrada"
fi

# -----------------------------------------------------------------------------
# Resultado final
# -----------------------------------------------------------------------------
separator
TOTAL=$((PASS + FAIL))
echo ""
echo -e "  Resultado: ${GREEN}${PASS} passed${NC} / ${RED}${FAIL} failed${NC} / ${TOTAL} total"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}  ✅ FASE 1 VALIDADA COM SUCESSO!${NC}"
  echo ""
  EXIT_CODE=0
else
  echo -e "${RED}  ❌ ${FAIL} verificação(ões) falharam — revise os erros acima.${NC}"
  echo ""
  EXIT_CODE=1
fi

separator
# cleanup é chamado automaticamente pelo trap EXIT
exit $EXIT_CODE
