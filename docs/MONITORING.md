# Monitoramento — Encontros Tech

## 1. Setup Prometheus

```bash
# Deploy
kubectl apply -f k8s/prometheus/prometheus-namespace.yaml
kubectl apply -f k8s/prometheus/prometheus-configmap.yaml
kubectl apply -f k8s/prometheus/prometheus-deployment.yaml
kubectl apply -f k8s/prometheus/prometheus-service.yaml

# Verificar
kubectl get pods -n monitoring -l app=prometheus
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
# Acesse: http://localhost:9090
```

### Scrape Targets
- **prometheus**: self-monitoring (localhost:9090)
- **encontros-tech-api**: pods com annotation `prometheus.io/scrape: "true"`
- **kubernetes-apiserver**: API server via HTTPS
- **kubernetes-nodes**: kubelets via HTTPS

---

## 2. Setup Grafana

```bash
kubectl apply -f k8s/grafana/grafana-datasources-configmap.yaml
kubectl apply -f k8s/grafana/grafana-deployment.yaml
kubectl apply -f k8s/grafana/grafana-service.yaml

# Acesso local
kubectl port-forward svc/grafana 3000:80 -n monitoring
```

**Login:** `admin` / `admin123`

**Adicionar datasource (se necessário):**
1. Configuration → Data Sources → Add data source
2. Selecione Prometheus
3. URL: `http://prometheus:9090`
4. Save & Test

---

## 3. Dashboards Disponíveis

| Dashboard | UID | Descrição |
|---|---|---|
| App Health | `et-app-health` | Request rate, error rate, latência P50/P95/P99 |
| Infrastructure | `et-infra` | CPU, Memory, Network, HPA replicas |
| Database | `et-database` | PostgreSQL CPU, Memory, PVC usage |

### Importar dashboards
```bash
bash scripts/import-grafana-dashboards.sh
```

---

## 4. Alertas Configurados

| Alerta | Threshold | Severidade | Ação |
|---|---|---|---|
| `HighLatency` | P95 > 1s por 5min | warning | Checar DB, slow queries |
| `HighErrorRate` | 5xx > 1% por 5min | critical | Checar logs, rollback |
| `PodCrashLoopBackOff` | restart > 0/h | critical | `kubectl logs`, rollback |
| `HighCPUUsage` | > 80% por 5min | warning | HPA vai escalar |
| `HighMemoryUsage` | > 400MB por 5min | warning | Checar memory leaks |
| `LowDiskSpace` | < 15% livre | critical | Expandir PVC |

---

## 5. Como Responder a Alertas

**HighLatency:**
```bash
kubectl top pods -n production
kubectl logs deployment/encontros-tech -n production | grep "slow"
```

**HighErrorRate:**
```bash
kubectl logs deployment/encontros-tech -n production --since=10m
kubectl rollout undo deployment/encontros-tech -n production
```

**HighCPU:**
```bash
kubectl get hpa -n production   # HPA já deve estar escalando
kubectl top pods -n production
```

---

## 6. Métricas Importantes

| Métrica | Tipo | Descrição |
|---|---|---|
| `http_requests_total` | Counter | Total de requests por método/endpoint/status |
| `http_request_duration_seconds` | Histogram | Latência das requests |
| `http_requests_active` | Gauge | Requests em andamento |
| `eventos_total` | Gauge | Total de eventos na plataforma |
| `container_cpu_usage_seconds_total` | Counter | CPU por container |
| `container_memory_usage_bytes` | Gauge | Memória por container |

---

## 7. Troubleshooting

**Prometheus não scraping:**
```bash
# Verificar targets
curl http://localhost:9090/api/v1/targets | python3 -m json.tool
# Checar annotations no pod
kubectl describe pod <pod> -n production | grep prometheus
```

**Grafana sem dados:**
```bash
# Testar datasource
curl http://localhost:9090/api/v1/query?query=up
# Verificar datasource no Grafana: Configuration → Data Sources → Test
```

**Alertas não disparando:**
```bash
# Verificar rules carregadas
curl http://localhost:9090/api/v1/rules | python3 -m json.tool
# Verificar se PrometheusRule foi aplicado
kubectl get prometheusrule -n monitoring
```
