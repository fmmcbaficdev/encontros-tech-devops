# Arquitetura — Encontros Tech DevOps

---

## 1. Containerização (Fase 1)

```
Dockerfile (Multi-Stage Build)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Stage 1: builder (python:3.11-slim)
   ├── apt install gcc
   ├── pip wheel -r requirements.txt
   └── /wheels/*.whl

 Stage 2: runtime (python:3.11-slim)
   ├── apt install curl          ← health check
   ├── useradd appuser (UID 1000) ← non-root
   ├── pip install --find-links /wheels
   └── COPY app/main.py /app/

 Resultado: 285 MB  (< 300 MB target)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

docker-compose.yaml (dev local)
  ┌─────────────┐    ┌──────────────┐    ┌──────────────┐
  │   et-app    │    │ et-postgres  │    │ et-pgadmin   │
  │  :8000      │───▶│  :5432       │    │  :5050       │
  │  FastAPI    │    │  postgres:15 │    │  pgadmin4    │
  │  (healthy)  │    │  (healthy)   │    │  (tools)     │
  └─────────────┘    └──────────────┘    └──────────────┘
        └───────────────────────────────────────┘
                    tech-network (bridge)
```

---

## 2. CI/CD Pipeline (Fase 2)

```
Developer
    │
    │ git push / PR
    ▼
GitHub Actions
    │
    ├─── Job: test ─────────────────────────────────────────┐
    │    ├── checkout                                        │
    │    ├── setup-python 3.11                              │
    │    ├── cache pip (~/.cache/pip)                       │
    │    ├── pip install -r requirements-dev.txt            │
    │    ├── ruff check (lint)                              │
    │    └── pytest --cov (coverage ≥ 70%)                  │
    │                                                        │
    ├─── Job: security ─────────────────────────────────────┤ (paralelo)
    │    ├── Trivy FS scan → SARIF → GitHub Security tab    │
    │    ├── pip-audit (CVEs em dependências)               │
    │    └── Gitleaks (segredos expostos)                   │
    │                                                        │
    └─── Job: docker [needs: test] ──────────────────────── ┘
         ├── docker/metadata-action (tags)
         ├── docker/build-push-action
         │    ├── cache-from/to: GitHub Actions cache
         │    └── tags: latest | branch | sha-<commit>
         └── push → docker.io/usuario/encontros-tech-api
                         │
                         │ [only main branch]
                         ▼
              Job: deploy [needs: docker]
                   ├── kubectl set image
                   ├── kubectl rollout status
                   └── health check pós-deploy
```

---

## 3. Kubernetes (Fase 3)

```
Namespace: production
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Internet
    │
    ▼
Service: LoadBalancer (port 80)
    │
    ▼
Deployment: encontros-tech
    ├── Pod 1 (node-A)  ─┐
    │   ├── FastAPI       │  Anti-affinity:
    │   ├── /health probe │  pods em nós diferentes
    │   └── /ready probe  │
    │                     │
    └── Pod 2 (node-B)  ─┘
        └── FastAPI

HPA: encontros-tech-hpa
    ├── minReplicas: 2
    ├── maxReplicas: 10
    ├── CPU target: 70%
    └── Memory target: 80%

ConfigMap: encontros-tech-config
    └── environment, log_level, workers, app_name

Secret: encontros-tech-secrets
    └── database_url, secret_key, jwt_secret

StatefulSet: postgres
    └── Pod: postgres-0 (node-X)
        ├── postgres:15-alpine
        ├── PVC: postgres-data-postgres-0 (20Gi)
        └── pg_isready health check

Service: postgres-headless (ClusterIP None)
    └── DNS: postgres-0.postgres-headless.production.svc.cluster.local

Ingress: encontros-tech (nginx)
    └── encontros-tech.example.com → Service:80 (TLS via cert-manager)
```

---

## 4. Observabilidade (Fase 4)

```
Namespace: monitoring
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

App Pod (/metrics)
    │  scrape a cada 15s
    ▼
Deployment: prometheus
    ├── prom/prometheus:v2.52.0
    ├── ConfigMap: prometheus-config
    │    └── prometheus.yml (scrape_configs)
    ├── ServiceAccount + ClusterRole (K8s API access)
    ├── Retenção: 30 dias
    └── Port: 9090

    │  datasource
    ▼
Deployment: grafana
    ├── grafana/grafana:10.4.2
    ├── ConfigMap: grafana-datasources → Prometheus
    ├── Dashboards:
    │    ├── App Health (req rate, latência, erros)
    │    ├── Infrastructure (CPU, Memory, HPA)
    │    └── Database (PostgreSQL stats)
    └── Port: 3000 → Service: 80

PrometheusRule: encontros-tech-alerts
    ├── HighLatency        (P95 > 1s / 5m / warning)
    ├── HighErrorRate      (5xx > 1% / 5m / critical)
    ├── PodCrashLoopBackOff (restart > 0/h / critical)
    ├── HighCPUUsage       (> 80% / 5m / warning)
    ├── HighMemoryUsage    (> 400MB / 5m / warning)
    └── LowDiskSpace       (< 15% / 5m / critical)
```

---

## 5. Fluxo de Dados

```
Requisição do Usuário:
  User → DNS → LoadBalancer → Service:80
             → Pod (FastAPI:8000)
             → [se necessário] StatefulSet PostgreSQL:5432
             ← JSON Response

Métricas:
  FastAPI /metrics → Prometheus (scrape 15s) → Grafana (dashboards)
                                             → AlertManager (se alerta)

Health Checks (Kubernetes):
  liveness  → GET /health  (30s delay, 10s interval) → reinicia pod se falhar
  readiness → GET /ready   (10s delay, 5s interval)  → remove do balanceador
  startup   → GET /health  (5s interval, 12 retries) → aguarda inicialização

CI/CD Flow:
  git push → GitHub Actions → pytest → Trivy → docker build
                           → docker push → kubectl rollout → health check
```
