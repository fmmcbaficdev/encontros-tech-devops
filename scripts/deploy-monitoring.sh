#!/usr/bin/env bash
# =============================================================================
# deploy-monitoring.sh — Deploy Prometheus + Grafana em Kubernetes
# Uso: bash scripts/deploy-monitoring.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")/k8s"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()     { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()      { echo -e "${GREEN}  ✓${NC} $*"; }
warn()    { echo -e "${YELLOW}  ⚠${NC} $*"; }
section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

echo -e "\n${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║    ENCONTROS TECH — DEPLOY MONITORING    ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}\n"

section "1. Namespace monitoring"
kubectl apply -f "${K8S_DIR}/prometheus/prometheus-namespace.yaml"
ok "Namespace monitoring criado"

section "2. Prometheus"
kubectl apply -f "${K8S_DIR}/prometheus/prometheus-configmap.yaml"
kubectl apply -f "${K8S_DIR}/prometheus/prometheus-deployment.yaml"
kubectl apply -f "${K8S_DIR}/prometheus/prometheus-service.yaml"
ok "Prometheus aplicado"

section "3. PrometheusRules (alertas)"
kubectl apply -f "${K8S_DIR}/prometheus-rules.yaml" || warn "PrometheusRule requer Prometheus Operator — ignorando"

section "4. Grafana"
kubectl apply -f "${K8S_DIR}/grafana/grafana-datasources-configmap.yaml"
kubectl apply -f "${K8S_DIR}/grafana/grafana-deployment.yaml"
kubectl apply -f "${K8S_DIR}/grafana/grafana-service.yaml"
ok "Grafana aplicado"

section "5. Aguardando pods ficarem prontos"
log "Prometheus..."
kubectl rollout status deployment/prometheus -n monitoring --timeout=3m && ok "Prometheus pronto"
log "Grafana..."
kubectl rollout status deployment/grafana -n monitoring --timeout=3m && ok "Grafana pronto"

section "6. Obtendo IPs"
PROM_IP=""
GRAF_IP=""
for i in $(seq 1 18); do
  PROM_IP=$(kubectl get svc prometheus -n monitoring \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  GRAF_IP=$(kubectl get svc grafana -n monitoring \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  [ -n "$PROM_IP" ] && [ -n "$GRAF_IP" ] && break
  log "Tentativa ${i}/18 — aguardando IPs..."
  sleep 10
done

PROM_IP="${PROM_IP:-<PENDING>}"
GRAF_IP="${GRAF_IP:-<PENDING>}"

section "7. Importando dashboards Grafana"
if [ "$GRAF_IP" != "<PENDING>" ]; then
  log "Aguardando Grafana inicializar (30s)..."
  sleep 30
  GRAFANA_URL="http://${GRAF_IP}" bash "${SCRIPT_DIR}/import-grafana-dashboards.sh" && ok "Dashboards importados"
else
  warn "IP do Grafana pendente — importe manualmente depois:"
  warn "  GRAFANA_URL=http://<IP> bash scripts/import-grafana-dashboards.sh"
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        MONITORING DEPLOYADO              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Prometheus : ${CYAN}http://${PROM_IP}:9090${NC}"
echo -e "  Grafana    : ${CYAN}http://${GRAF_IP}${NC}  (admin/admin123)"
echo ""
echo -e "  Verificar pods:"
echo -e "    kubectl get pods -n monitoring"
echo -e "  Verificar targets Prometheus:"
echo -e "    http://${PROM_IP}:9090/targets"
echo ""
