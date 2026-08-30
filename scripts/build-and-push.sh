#!/usr/bin/env bash
# =============================================================================
# build-and-push.sh — Build e Push da imagem Docker
# Uso: bash scripts/build-and-push.sh [IMAGE_TAG]
# Exemplo: bash scripts/build-and-push.sh v1.2.3
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------
DOCKER_USERNAME="${DOCKER_USERNAME:-}"
IMAGE_NAME="${IMAGE_NAME:-encontros-tech-api}"
IMAGE_TAG="${1:-latest}"
MAX_SIZE_MB=300
REGISTRY="${REGISTRY:-docker.io}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()     { echo -e "${BLUE}[INFO]${NC}    $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}      $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail()    { echo -e "${RED}[ERRO]${NC}    $*"; }
section() { echo -e "\n${CYAN}▶ $*${NC}"; }

cd "$PROJECT_ROOT"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     ENCONTROS TECH — BUILD & PUSH        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ---------------------------------------------------------------------------
# Validações iniciais
# ---------------------------------------------------------------------------
section "Validando pré-requisitos..."

if ! command -v docker &>/dev/null; then
  fail "docker não encontrado. Instale o Docker Desktop."; exit 1
fi
ok "docker $(docker --version | awk '{print $3}' | tr -d ',')"

if [ -z "$DOCKER_USERNAME" ]; then
  warn "DOCKER_USERNAME não definido."
  read -rp "  Docker Hub username: " DOCKER_USERNAME
  [ -z "$DOCKER_USERNAME" ] && { fail "Username não pode ser vazio."; exit 1; }
fi
ok "Usuário Docker Hub: ${DOCKER_USERNAME}"

if [ ! -f "docker/Dockerfile" ]; then
  fail "docker/Dockerfile não encontrado. Execute do diretório raiz do projeto."; exit 1
fi
ok "Dockerfile encontrado"

# ---------------------------------------------------------------------------
# Definir tags
# ---------------------------------------------------------------------------
section "Definindo tags..."

FULL_IMAGE="${REGISTRY}/${DOCKER_USERNAME}/${IMAGE_NAME}"
SHORT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "nogit")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '-' || echo "nobranch")
BUILD_DATE=$(date -u +%Y%m%d%H%M%S)

TAG_USER="${FULL_IMAGE}:${IMAGE_TAG}"
TAG_SHA="${FULL_IMAGE}:sha-${SHORT_SHA}"
TAG_BRANCH="${FULL_IMAGE}:${BRANCH}"
TAG_DATE="${FULL_IMAGE}:build-${BUILD_DATE}"

log "Imagem base:   ${FULL_IMAGE}"
log "Tags a criar:"
log "  → ${IMAGE_TAG}"
log "  → sha-${SHORT_SHA}"
log "  → ${BRANCH}"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
section "Fazendo build da imagem..."
START_TIME=$(date +%s)

docker build \
  --file docker/Dockerfile \
  --tag "${TAG_USER}" \
  --tag "${TAG_SHA}" \
  --tag "${TAG_BRANCH}" \
  --label "build.date=${BUILD_DATE}" \
  --label "build.sha=${SHORT_SHA}" \
  --label "build.branch=${BRANCH}" \
  .

END_TIME=$(date +%s)
BUILD_DURATION=$((END_TIME - START_TIME))
ok "Build concluído em ${BUILD_DURATION}s"

# ---------------------------------------------------------------------------
# Verificar tamanho
# ---------------------------------------------------------------------------
section "Verificando tamanho da imagem..."

SIZE_RAW=$(docker image inspect "${TAG_USER}" --format='{{.VirtualSize}}')
SIZE_MB=$(python3 -c "print(round($SIZE_RAW / 1024 / 1024, 1))")
SIZE_INT=$(python3 -c "print(int($SIZE_RAW / 1024 / 1024))")

log "Tamanho: ${SIZE_MB} MB (limite: ${MAX_SIZE_MB} MB)"

if [ "$SIZE_INT" -gt "$MAX_SIZE_MB" ]; then
  warn "Imagem acima de ${MAX_SIZE_MB} MB! Considere otimizar o Dockerfile."
else
  ok "Tamanho OK: ${SIZE_MB} MB"
fi

# ---------------------------------------------------------------------------
# Login no Docker Hub (se necessário)
# ---------------------------------------------------------------------------
section "Autenticando no Docker Hub..."

if docker info 2>/dev/null | grep -q "Username: ${DOCKER_USERNAME}"; then
  ok "Já autenticado como ${DOCKER_USERNAME}"
else
  log "Fazendo login no Docker Hub..."
  if [ -n "${DOCKER_PASSWORD:-}" ]; then
    echo "$DOCKER_PASSWORD" | docker login "$REGISTRY" -u "$DOCKER_USERNAME" --password-stdin
  else
    docker login "$REGISTRY" -u "$DOCKER_USERNAME"
  fi
  ok "Login realizado"
fi

# ---------------------------------------------------------------------------
# Push
# ---------------------------------------------------------------------------
section "Fazendo push das tags..."

for TAG in "${TAG_USER}" "${TAG_SHA}" "${TAG_BRANCH}"; do
  log "Pushing: ${TAG}"
  docker push "${TAG}" && ok "${TAG}" || { fail "Falha ao push ${TAG}"; exit 1; }
done

# ---------------------------------------------------------------------------
# Verificar push
# ---------------------------------------------------------------------------
section "Verificando push..."

MANIFEST=$(docker manifest inspect "${TAG_SHA}" 2>/dev/null && echo "ok" || echo "fail")
if [ "$MANIFEST" = "ok" ]; then
  ok "Push verificado: ${TAG_SHA}"
else
  warn "Não foi possível verificar o manifest (pode ser delay do registry)"
fi

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           BUILD & PUSH CONCLUÍDO         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Imagem:   ${CYAN}${FULL_IMAGE}${NC}"
echo -e "  Tags:"
echo -e "    ${GREEN}✓${NC} :${IMAGE_TAG}"
echo -e "    ${GREEN}✓${NC} :sha-${SHORT_SHA}"
echo -e "    ${GREEN}✓${NC} :${BRANCH}"
echo -e "  Tamanho:  ${SIZE_MB} MB"
echo -e "  Tempo:    ${BUILD_DURATION}s"
echo ""
echo -e "  Para rodar localmente:"
echo -e "  ${CYAN}docker run -p 8000:8000 ${TAG_SHA}${NC}"
echo ""
