# Encontros Tech — DevOps Modernizado

Pipeline completo de CI/CD com Docker, Kubernetes e Observabilidade.
Bootcamp DevOps Pro — 8 semanas.

---

## Quick Start

```bash
# Desenvolvimento local
docker compose --env-file .env.docker up -d
curl http://localhost:8000/health

# Validação completa
bash scripts/test-local.sh

# Build e push
export DOCKER_USERNAME=seu-usuario
bash scripts/build-and-push.sh latest

# Deploy Kubernetes
bash scripts/deploy.sh production latest

# Deploy monitoramento
bash scripts/deploy-monitoring.sh
```

---

## Estrutura

```
encontros-tech-devops/
├── app/
│   ├── main.py                  # FastAPI (6 endpoints)
│   ├── requirements.txt         # Dependências produção
│   ├── requirements-dev.txt     # Dependências dev/teste
│   └── tests/
│       ├── test_api.py          # 40+ testes unitários
│       └── test_integration.py  # Testes end-to-end
├── docker/
│   ├── Dockerfile               # Multi-stage (285 MB)
│   └── .dockerignore
├── k8s/
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── secrets.yaml
│   ├── deployment.yaml          # 2-10 réplicas, HPA
│   ├── service.yaml             # LoadBalancer
│   ├── hpa.yaml                 # CPU 70% / Mem 80%
│   ├── statefulset-postgres.yaml
│   ├── ingress.yaml
│   ├── prometheus/              # Stack de métricas
│   └── grafana/                 # Dashboards
├── scripts/
│   ├── test-local.sh            # 30 verificações
│   ├── build-and-push.sh        # Build + push multi-tag
│   ├── integration-test.sh      # Testes com compose
│   ├── deploy.sh                # Deploy K8s completo
│   ├── deploy-monitoring.sh     # Prometheus + Grafana
│   └── demo.sh                  # Demo interativo
├── docs/
│   ├── ARCHITECTURE.md
│   ├── MONITORING.md
│   ├── RUNBOOK.md
│   ├── INGRESS_SETUP.md
│   └── PRESENTATION.md
└── .github/workflows/
    ├── ci-cd.yml                # 4 jobs: test/security/docker/deploy
    └── security.yml             # Trivy + pip-audit + Gitleaks
```

---

## API Endpoints

| Método | Rota | Descrição |
|---|---|---|
| GET | `/health` | Liveness probe |
| GET | `/ready` | Readiness probe |
| GET | `/metrics` | Prometheus scrape |
| GET | `/api/v2/eventos` | Listagem paginada |
| GET | `/api/v2/eventos/{id}` | Busca por ID |
| GET | `/docs` | Swagger UI |

---

## Testes

```bash
cd app
pip install -r requirements-dev.txt

# Testes unitários
pytest tests/test_api.py -v

# Testes de integração
bash scripts/integration-test.sh

# Coverage
pytest tests/ --cov=. --cov-report=term-missing
```

---

## CI/CD — GitHub Actions

| Job | Trigger | Descrição |
|---|---|---|
| `test` | push/PR | pytest + cobertura + lint |
| `security` | push/PR | Trivy + pip-audit + Gitleaks |
| `docker` | push (após test) | Build + push multi-tag |
| `deploy` | push main | kubectl rollout |

**Secrets necessários:** `DOCKER_USERNAME`, `DOCKER_PASSWORD`, `KUBECONFIG`

---

## Monitoramento

```bash
# Port-forward local
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
kubectl port-forward svc/grafana 3000:80 -n monitoring
```

- **Prometheus:** `http://localhost:9090`
- **Grafana:** `http://localhost:3000` — `admin` / `admin123`

**Dashboards:** App Health | Infrastructure | Database

**Alertas:** HighLatency | HighErrorRate | CrashLoopBackOff | HighCPU | LowDisk

---

## Documentação

| Documento | Descrição |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Diagramas de arquitetura |
| [docs/MONITORING.md](docs/MONITORING.md) | Setup e uso do monitoramento |
| [docs/RUNBOOK.md](docs/RUNBOOK.md) | Guia de resposta a incidentes |
| [docs/INGRESS_SETUP.md](docs/INGRESS_SETUP.md) | Configurar nginx + SSL |
| [docs/PRESENTATION.md](docs/PRESENTATION.md) | Impacto de negócio |

---

## Fases do Bootcamp

- [x] Fase 1 — Containerização (FastAPI + Docker + Compose)
- [x] Fase 2 — CI/CD (GitHub Actions)
- [x] Fase 3 — Kubernetes (Deploy + HPA + StatefulSet)
- [x] Fase 4 — Observabilidade (Prometheus + Grafana + Alertas)
