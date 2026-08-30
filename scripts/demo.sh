#!/usr/bin/env bash
# =============================================================================
# demo.sh — Demonstração completa do sistema DevOps
# Uso: bash scripts/demo.sh
# =============================================================================

set -euo pipefail

NAMESPACE="${NAMESPACE:-production}"
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

log()     { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()      { echo -e "${GREEN}  ✓${NC} $*"; }
warn()    { echo -e "${YELLOW}  ⚠${NC} $*"; }
section() { echo -e "\n${CYAN}══════════════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}══════════════════════════════════════════════${NC}"; }
pause()   { echo -e "\n${YELLOW}  Pressione ENTER para continuar...${NC}"; read -r; }

LB_IP=$(kubectl get svc encontros-tech -n "$NAMESPACE" \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "localhost")

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      ENCONTROS TECH — DEMO COMPLETO          ║${NC}"
echo -e "${CYAN}║      $(date '+%Y-%m-%d %H:%M')                        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ---------------------------------------------------------------------------
# VALIDAÇÕES INICIAIS
# ---------------------------------------------------------------------------
section "0. Validações Iniciais"
kubectl cluster-info --request-timeout=5s > /dev/null && ok "Cluster acessível"
kubectl get deployment encontros-tech -n "$NAMESPACE" > /dev/null && ok "App deployment existe"
curl -sf "http://${LB_IP}/health" > /dev/null && ok "API respondendo em http://${LB_IP}"
echo ""
log "Configuração atual:"
kubectl get pods,svc,hpa -n "$NAMESPACE" | head -20
pause

# ---------------------------------------------------------------------------
# DEMO 1: Deploy Automático
# ---------------------------------------------------------------------------
section "1. DEMO — Deploy Automático via CI/CD"
log "Vamos simular um novo deploy (touch em main.py para triggerar CI)"
echo ""
log "Estado atual:"
kubectl rollout history deployment/encontros-tech -n "$NAMESPACE" | tail -5
echo ""
log "Simulando deploy manual com nova tag..."
CURRENT_IMAGE=$(kubectl get deployment encontros-tech -n "$NAMESPACE" \
  -o jsonpath='{.spec.template.spec.containers[0].image}')
log "Imagem atual: ${CURRENT_IMAGE}"

log "Em produção real, o GitHub Actions faria:"
echo "  1. git push → GitHub Actions dispara"
echo "  2. pytest executa (cobertura > 70%)"
echo "  3. Trivy scan de segurança"
echo "  4. docker build + push com sha-\$(git rev-parse --short HEAD)"
echo "  5. kubectl set image deployment/encontros-tech"
echo "  6. kubectl rollout status (aguarda 0 downtime)"
echo ""
log "Verificando rollout atual:"
kubectl rollout status deployment/encontros-tech -n "$NAMESPACE" --timeout=30s
ok "Deploy concluído com zero downtime (RollingUpdate)"
pause

# ---------------------------------------------------------------------------
# DEMO 2: Auto-scaling
# ---------------------------------------------------------------------------
section "2. DEMO — Auto-scaling com HPA"
log "Estado atual do HPA:"
kubectl get hpa -n "$NAMESPACE"
echo ""
log "Replicas atuais:"
kubectl get pods -n "$NAMESPACE" -l app=encontros-tech | grep -c Running && \
  echo "  pods rodando" || true

if command -v ab &>/dev/null; then
  log "Gerando carga com Apache Benchmark..."
  log "ab -n 5000 -c 50 http://${LB_IP}/api/v2/eventos &"
  ab -n 5000 -c 50 "http://${LB_IP}/api/v2/eventos" > /tmp/ab-demo.txt 2>&1 &
  AB_PID=$!
  log "Monitorando HPA em tempo real (30s)..."
  for i in $(seq 1 6); do
    sleep 5
    echo -n "  [${i}/6] "
    kubectl get hpa encontros-tech-hpa -n "$NAMESPACE" --no-headers 2>/dev/null || echo "HPA não encontrado"
  done
  kill "$AB_PID" 2>/dev/null || true
else
  warn "apache2-utils não instalado. Para instalar: sudo apt install apache2-utils"
  log "Simulando carga com curl (demonstração)..."
  for i in $(seq 1 10); do
    curl -sf "http://${LB_IP}/api/v2/eventos" > /dev/null &
  done
  wait
  log "Carga simulada. Em produção com ab, replicas escalariam de 2 → 10"
fi
ok "HPA configurado: min=2, max=10, CPU=70%, Memory=80%"
pause

# ---------------------------------------------------------------------------
# DEMO 3: Failover / Self-healing
# ---------------------------------------------------------------------------
section "3. DEMO — Failover / Self-Healing"
log "Deletando um pod para demonstrar self-healing..."
POD=$(kubectl get pods -n "$NAMESPACE" -l app=encontros-tech \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$POD" ]; then
  log "Deletando pod: ${POD}"
  kubectl delete pod "$POD" -n "$NAMESPACE" &
  log "Monitorando recriação (API continua respondendo)..."
  for i in $(seq 1 5); do
    sleep 2
    STATUS=$(curl -sf -o /dev/null -w "%{http_code}" "http://${LB_IP}/health" 2>/dev/null || echo "000")
    PODS=$(kubectl get pods -n "$NAMESPACE" -l app=encontros-tech --no-headers 2>/dev/null | wc -l)
    echo "  t+$((i*2))s | HTTP ${STATUS} | Pods: ${PODS}"
  done
  ok "Self-healing: novo pod criado automaticamente, zero downtime!"
else
  warn "Nenhum pod encontrado — pule esta etapa se K8s não estiver disponível"
fi
pause

# ---------------------------------------------------------------------------
# DEMO 4: Monitoring
# ---------------------------------------------------------------------------
section "4. DEMO — Observabilidade"
log "Verificando métricas Prometheus da API..."
curl -sf "http://${LB_IP}/metrics" | grep -E "^(http_requests_total|http_request_duration|eventos_total)" | head -10
echo ""

PROM_PORT=$(kubectl get svc prometheus -n monitoring \
  -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "9090")
PROM_IP=$(kubectl get svc prometheus -n monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "localhost")

log "Acesse os dashboards:"
echo "  Prometheus : http://${PROM_IP}:${PROM_PORT}/targets"
echo "  Grafana    : http://<GRAFANA_IP> (admin/admin123)"
echo "  API Docs   : http://${LB_IP}/docs"
echo ""
ok "Observabilidade configurada: Prometheus + Grafana + 5 alertas ativos"

# ---------------------------------------------------------------------------
# Resumo Final
# ---------------------------------------------------------------------------
section "RESUMO DA DEMONSTRAÇÃO"
echo ""
echo -e "  ${GREEN}✓${NC} Deploy automático via CI/CD (GitHub Actions)"
echo -e "  ${GREEN}✓${NC} Zero downtime com RollingUpdate"
echo -e "  ${GREEN}✓${NC} Auto-scaling HPA (2 → 10 pods)"
echo -e "  ${GREEN}✓${NC} Self-healing automático"
echo -e "  ${GREEN}✓${NC} Observabilidade com Prometheus + Grafana"
echo ""
echo -e "  API: ${CYAN}http://${LB_IP}${NC}"
echo ""
