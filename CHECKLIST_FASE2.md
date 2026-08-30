# Checklist — Fase 2: CI/CD Pipeline

> Bootcamp DevOps Pro — Semanas 3-4
> Status: ✅ Concluída

---

## Arquivos Criados

| Arquivo | Descrição | Status |
|---|---|---|
| `.github/workflows/ci-cd.yml` | Pipeline CI/CD completo (4 jobs) | ✅ |
| `.github/workflows/security.yml` | SAST adicional (Trivy, pip-audit, Gitleaks) | ✅ |
| `app/tests/test_integration.py` | Testes de integração end-to-end | ✅ |
| `scripts/integration-test.sh` | Script de integração com docker-compose | ✅ |
| `scripts/build-and-push.sh` | Build e push da imagem com múltiplas tags | ✅ |
| `CHECKLIST_FASE2.md` | Este arquivo | ✅ |

---

## Pipeline CI/CD — Jobs

| Job | Trigger | Descrição |
|---|---|---|
| `test` | Push/PR | pytest + coverage (≥ 70%) + lint |
| `security` | Push/PR | Trivy filesystem scan → GitHub Security tab |
| `docker` | Push (após test OK) | Build + push multi-tag para Docker Hub |
| `deploy` | Push em `main` only | kubectl set image + rollout + health check |

### Fluxo de execução

```
push → test ──────────────────────────────────→ (paralelo)
         │                                        security
         └── [OK] → docker → [main] → deploy
```

---

## Configurar GitHub Actions — Passo a Passo

### 1. Criar repositório GitHub

```bash
gh repo create encontros-tech-devops --public
# ou via github.com → New repository
```

### 2. Adicionar Secrets no repositório

Acesse: `Settings → Secrets and variables → Actions → New repository secret`

| Secret | Valor | Obrigatório |
|---|---|---|
| `DOCKER_USERNAME` | Seu usuário do Docker Hub | ✅ |
| `DOCKER_PASSWORD` | Token do Docker Hub (não senha!) | ✅ |
| `KUBECONFIG` | `base64 ~/.kube/config` | Apenas para deploy K8s |

**Gerar token Docker Hub:**
```
hub.docker.com → Account Settings → Security → New Access Token
```

**Codificar kubeconfig em base64:**
```bash
cat ~/.kube/config | base64 | tr -d '\n'
```

### 3. Primeiro push para ativar o pipeline

```bash
git push origin main
```

### 4. Verificar pipeline

```
github.com/SEU_USUARIO/encontros-tech-devops → aba Actions
```

---

## Métricas Esperadas

| Métrica | Target | Observação |
|---|---|---|
| Tempo total do pipeline | 3-5 min | Com cache quente |
| Test coverage | ≥ 70% | Configurado em pytest.ini |
| Tamanho da imagem | < 300 MB | Validado no job docker |
| Vulnerabilidades CRITICAL | 0 | Trivy com exit-code=0 (não falha, registra) |
| Tempo de build Docker | < 2 min | Com GitHub Actions cache |

---

## Testar Localmente

### Simular job de testes
```bash
cd app
pip install -r requirements-dev.txt pytest-cov
pytest tests/ --cov=. --cov-report=term-missing -v
```

### Build e push manual
```bash
export DOCKER_USERNAME=seu-usuario
bash scripts/build-and-push.sh latest
```

### Testes de integração com docker-compose
```bash
bash scripts/integration-test.sh
```

### Scan de segurança local (requer Trivy instalado)
```bash
# Instalar Trivy
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# Rodar scan
trivy fs . --severity CRITICAL,HIGH
```

---

## Commits da Fase 2

| Commit | Descrição |
|---|---|
| `feat(ci): adiciona pipeline GitHub Actions (4 jobs)` | ci-cd.yml + security.yml |
| `test(integration): adiciona testes de integração` | test_integration.py |
| `feat(scripts): build-and-push e integration-test` | Scripts de CI local |

---

## Próximos Passos — Fase 3

- [ ] Criar manifests Kubernetes (namespace, configmap, secrets)
- [ ] Criar Deployment FastAPI com probes e resources
- [ ] Criar Service LoadBalancer + HPA
- [ ] Criar StatefulSet PostgreSQL
- [ ] Script de deploy automatizado
