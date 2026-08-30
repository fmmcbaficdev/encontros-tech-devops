#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Deploy completo em Kubernetes
# Uso: bash scripts/deploy.sh [NAMESPACE] [IMAGE_TAG]
# Exemplo: bash scripts/deploy.sh production sha-a1b2c3d
# =============================================================================

set -euo pipefail

NAMESPACE="${1:-production}"
IMAGE_TAG="${2:-latest}"
DOCKER_USERNAME="${DOCKER_USERNAME:-DOCKER_USERNAME}"
IMAGE="docker.io/${DOCKER_USERNAME}/encontros-tech-api:${IMAGE_TAG}"
K8S_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/k8s"
ROLLOUT_TIMEOUT="5m"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()     { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()      { echo -e "${GREEN}  ✓${NC} $*"; }
warn()    { echo -e "${YELLOW}  ⚠${NC} $*"; }
fail()    { echo -e "${RED}  ✗${NC} $*"; }
section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        ENCONTROS TECH — DEPLOY K8S           ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo -e "  Namespace : ${NAMESPACE}"
echo -e "  Imagem    : ${IMAGE}"
echo -e "  Timestamp : $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# ---------------------------------------------------------------------------
# 1. Validar kubeconfig
# ---------------------------------------------------------------------------
section "1. Validando kubeconfig"
if [ ! -f "${KUBECONFIG:-$HOME/.kube/config}" ]; then
  fail "kubeconfig não encontrado em ${KUBECONFIG:-$HOME/.kube/config}"
  exit 1
fi
kubectl cluster-info --request-timeout=10s > /dev/null 2>&1 && ok "Cluster acessível" || {
  fail "Não foi possível conectar ao cluster"
  exit 1
}
CLUSTER=$(kubectl config current-context)
ok "Contexto: ${CLUSTER}"

# ---------------------------------------------------------------------------
# 2. Criar namespace
# ---------------------------------------------------------------------------
section "2. Namespace: ${NAMESPACE}"
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
  ok "Namespace '${NAMESPACE}' já existe"
else
  kubectl apply -f "${K8S_DIR}/namespace.yaml"
  ok "Namespace '${NAMESPACE}' criado"
fi

# ---------------------------------------------------------------------------
# 3. ConfigMap
# ---------------------------------------------------------------------------
section "3. ConfigMap"
kubectl apply -f "${K8S_DIR}/configmap.yaml" -n "$NAMESPACE"
ok "ConfigMap aplicado"

# ---------------------------------------------------------------------------
# 4. Secrets
# ---------------------------------------------------------------------------
section "4. Secrets"
warn "Aplicando secrets com valores de EXEMPLO — substitua em produção!"
kubectl apply -f "${K8S_DIR}/secrets.yaml" -n "$NAMESPACE"
ok "Secrets aplicados (valores de exemplo)"

# ---------------------------------------------------------------------------
# 5. Storage
# ---------------------------------------------------------------------------
section "5. Storage (PV/PVC)"
kubectl apply -f "${K8S_DIR}/storage.yaml" || warn "Storage pode já existir — ignorando"
ok "Storage verificado"

# ---------------------------------------------------------------------------
# 6. PostgreSQL (StatefulSet + Headless Service)
# ---------------------------------------------------------------------------
section "6. PostgreSQL"
kubectl apply -f "${K8S_DIR}/postgres-headless-service.yaml" -n "$NAMESPACE"
kubectl apply -f "${K8S_DIR}/statefulset-postgres.yaml" -n "$NAMESPACE"
ok "PostgreSQL StatefulSet aplicado"

log "Aguardando PostgreSQL ficar pronto (até 3 min)..."
kubectl rollout status statefulset/postgres \
  -n "$NAMESPACE" \
  --timeout=3m && ok "PostgreSQL pronto" || warn "PostgreSQL ainda iniciando"

# ---------------------------------------------------------------------------
# 7. Deployment da aplicação
# ---------------------------------------------------------------------------
section "7. Deployment FastAPI"
kubectl apply -f "${K8S_DIR}/deployment.yaml" -n "$NAMESPACE"
ok "Deployment aplicado"

# ---------------------------------------------------------------------------
# 8. Service
# ---------------------------------------------------------------------------
section "8. Service (LoadBalancer)"
kubectl apply -f "${K8S_DIR}/service.yaml" -n "$NAMESPACE"
ok "Service aplicado"

# ---------------------------------------------------------------------------
# 9. HPA
# ---------------------------------------------------------------------------
section "9. HorizontalPodAutoscaler"
kubectl apply -f "${K8S_DIR}/hpa.yaml" -n "$NAMESPACE"
ok "HPA aplicado (min:2 / max:10)"

# ---------------------------------------------------------------------------
# 10. Atualizar imagem
# ---------------------------------------------------------------------------
section "10. Atualizando imagem"
log "Imagem: ${IMAGE}"
kubectl set image deployment/encontros-tech \
  app="${IMAGE}" \
  -n "$NAMESPACE"
ok "Imagem atualizada: ${IMAGE}"

# ---------------------------------------------------------------------------
# 11. Aguardar rollout
# ---------------------------------------------------------------------------
section "11. Rollout (timeout: ${ROLLOUT_TIMEOUT})"
if kubectl rollout status deployment/encontros-tech \
    -n "$NAMESPACE" \
    --timeout="$ROLLOUT_TIMEOUT"; then
  ok "Rollout concluído com sucesso"
else
  fail "Rollout falhou ou timeout atingido"
  log "Últimos eventos:"
  kubectl get events -n "$NAMESPACE" \
    --sort-by='.lastTimestamp' | tail -10
  log "Para fazer rollback: kubectl rollout undo deployment/encontros-tech -n ${NAMESPACE}"
  exit 1
fi

# ---------------------------------------------------------------------------
# 12. Verificar pods
# ---------------------------------------------------------------------------
section "12. Verificando pods"
kubectl get pods -n "$NAMESPACE" -l app=encontros-tech -o wide
READY=$(kubectl get deployment encontros-tech -n "$NAMESPACE" \
  -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
DESIRED=$(kubectl get deployment encontros-tech -n "$NAMESPACE" \
  -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "2")
ok "Pods prontos: ${READY}/${DESIRED}"

# ---------------------------------------------------------------------------
# 13. Obter LoadBalancer IP
# ---------------------------------------------------------------------------
section "13. LoadBalancer IP"
log "Aguardando IP do LoadBalancer (pode levar 1-2 min)..."
LB_IP=""
for i in $(seq 1 12); do
  LB_IP=$(kubectl get svc encontros-tech -n "$NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  [ -n "$LB_IP" ] && break
  log "Tentativa ${i}/12 — aguardando..."
  sleep 10
done

if [ -z "$LB_IP" ]; then
  warn "IP não disponível ainda — verifique com: kubectl get svc -n ${NAMESPACE}"
  LB_IP="<PENDING>"
fi

# ---------------------------------------------------------------------------
# 14. Health check
# ---------------------------------------------------------------------------
section "14. Health check pós-deploy"
if [ "$LB_IP" != "<PENDING>" ]; then
  log "Testando http://${LB_IP}/health ..."
  for i in 1 2 3; do
    STATUS=$(curl -sf -o /dev/null -w "%{http_code}" "http://${LB_IP}/health" 2>/dev/null || echo "000")
    if [ "$STATUS" = "200" ]; then
      ok "Health check OK — HTTP ${STATUS}"
      break
    fi
    warn "Tentativa ${i}/3 — HTTP ${STATUS}, aguardando 10s..."
    sleep 10
  done
else
  warn "IP pendente — health check ignorado"
fi

# ---------------------------------------------------------------------------
# Resumo Final
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              DEPLOY CONCLUÍDO                ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Namespace   : ${NAMESPACE}"
echo -e "  Imagem      : ${IMAGE}"
echo -e "  Pods prontos: ${READY}/${DESIRED}"
echo ""
echo -e "  Endpoints:"
echo -e "    API     : ${CYAN}http://${LB_IP}/api/v2/eventos${NC}"
echo -e "    Health  : ${CYAN}http://${LB_IP}/health${NC}"
echo -e "    Metrics : ${CYAN}http://${LB_IP}/metrics${NC}"
echo -e "    Docs    : ${CYAN}http://${LB_IP}/docs${NC}"
echo ""
echo -e "  Comandos úteis:"
echo -e "    kubectl get pods -n ${NAMESPACE}"
echo -e "    kubectl get hpa -n ${NAMESPACE}"
echo -e "    kubectl logs -f deployment/encontros-tech -n ${NAMESPACE}"
echo -e "    kubectl rollout undo deployment/encontros-tech -n ${NAMESPACE}"
echo ""
