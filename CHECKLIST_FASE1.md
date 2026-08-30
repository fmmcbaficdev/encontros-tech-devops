# Checklist — Fase 1: Containerização

> Bootcamp DevOps Pro — Semanas 1-2
> Status: ✅ Concluída

---

## Arquivos Criados

### Aplicação (`app/`)
| Arquivo | Descrição | Status |
|---|---|---|
| `app/main.py` | FastAPI com 6 endpoints, logging JSON, métricas Prometheus | ✅ |
| `app/requirements.txt` | Dependências de produção | ✅ |
| `app/requirements-dev.txt` | Dependências de teste (pytest, httpx) | ✅ |
| `app/.env.example` | Template de variáveis de ambiente | ✅ |

### Testes (`app/tests/`)
| Arquivo | Descrição | Status |
|---|---|---|
| `app/tests/__init__.py` | Módulo de testes | ✅ |
| `app/tests/test_api.py` | 6 classes, 40+ asserções, parametrização | ✅ |
| `app/pytest.ini` | Configuração pytest para CI/CD | ✅ |

### Docker
| Arquivo | Descrição | Status |
|---|---|---|
| `docker/Dockerfile` | Multi-stage build (builder + runtime) | ✅ |
| `docker/.dockerignore` | Exclusões para otimizar contexto de build | ✅ |
| `docker-compose.yaml` | Stack local (app + postgres + pgadmin) | ✅ |
| `.env.docker.example` | Template de variáveis do compose | ✅ |

### Scripts e Documentação
| Arquivo | Descrição | Status |
|---|---|---|
| `scripts/test-local.sh` | Validação automatizada completa | ✅ |
| `CHECKLIST_FASE1.md` | Este arquivo | ✅ |

---

## Endpoints Implementados

| Método | Rota | Finalidade | Validado |
|---|---|---|---|
| GET | `/` | Info geral da API | ✅ |
| GET | `/health` | Liveness probe — status, uptime, versão | ✅ |
| GET | `/ready` | Readiness probe — checklist de dependências | ✅ |
| GET | `/metrics` | Scrape Prometheus (Counter, Histogram, Gauge) | ✅ |
| GET | `/api/v2/eventos` | Listagem paginada com filtro por categoria | ✅ |
| GET | `/api/v2/eventos/{id}` | Busca evento por ID | ✅ |
| GET | `/docs` | Swagger UI auto-gerado pelo FastAPI | ✅ |

---

## Validação Técnica

### Docker Image
| Critério | Resultado |
|---|---|
| Build multi-stage (builder + runtime) | ✅ |
| Base: `python:3.11-slim` | ✅ |
| Usuário não-root (`appuser`, UID 1000) | ✅ |
| Tamanho da imagem | ✅ **285 MB** (limite: 300 MB) |
| Health check nativo Docker | ✅ |
| Variáveis de ambiente configuráveis | ✅ |

### docker-compose
| Critério | Resultado |
|---|---|
| Serviço `app` com hot-reload | ✅ |
| Serviço `postgres:15-alpine` | ✅ |
| `pg_isready` health check no postgres | ✅ |
| `depends_on` com `condition: service_healthy` | ✅ |
| Serviço `pgadmin` isolado no profile `tools` | ✅ |
| Volume nomeado `postgres_data` | ✅ |
| Rede customizada `tech-network` | ✅ |

---

## Como Testar

### Validação automatizada (recomendado)
```bash
bash scripts/test-local.sh
```

### Subir o stack manualmente
```bash
# Stack básico (app + postgres)
docker compose --env-file .env.docker up -d

# Com pgAdmin
docker compose --env-file .env.docker --profile tools up -d
```

### Testar endpoints manualmente
```bash
# Health check
curl http://localhost:8000/health

# Readiness probe
curl http://localhost:8000/ready

# Métricas Prometheus
curl http://localhost:8000/metrics

# Listar eventos
curl http://localhost:8000/api/v2/eventos

# Filtrar por categoria
curl "http://localhost:8000/api/v2/eventos?categoria=DevOps"

# Buscar por ID
curl http://localhost:8000/api/v2/eventos/1

# Swagger UI
open http://localhost:8000/docs
```

### Rodar testes unitários (requer dependências instaladas)
```bash
cd app
pip install -r requirements-dev.txt
pytest tests/ -v
```

### Parar o stack
```bash
docker compose --env-file .env.docker down
docker compose --env-file .env.docker down --volumes  # remove dados do postgres
```

---

## Git — Commits da Fase 1

| Commit | Descrição |
|---|---|
| `e993593` | `chore: initial project setup` |
| `69fc284` | `feat(app): adiciona aplicação FastAPI base` |
| `87fdff2` | `test(app): adiciona suite de testes unitários FastAPI` |
| `a586d4c` | `feat(docker): adiciona Dockerfile multi-stage otimizado` |
| `a015b28` | `feat(compose): adiciona docker-compose.yaml para desenvolvimento local` |

---

## Próximos Passos — Fase 2

- [ ] Pipeline CI/CD com GitHub Actions
- [ ] Build e push automático de imagem para registry
- [ ] Execução de testes no pipeline
- [ ] Scan de vulnerabilidades (Trivy)
