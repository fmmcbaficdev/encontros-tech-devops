# Checklist — Fase 3: Kubernetes

> Bootcamp DevOps Pro — Semanas 5-6
> Status: ✅ Concluída

## Pré-requisitos
- [ ] Cluster Kubernetes criado (EKS / GKE / AKS / kind / minikube)
- [ ] kubectl configurado: `kubectl get nodes`
- [ ] kubeconfig em `$HOME/.kube/config`
- [ ] Imagem publicada no Docker Hub (Fase 2)

## Arquivos Criados

| Arquivo | Descrição | Status |
|---|---|---|
| `k8s/namespace.yaml` | Namespace production com label monitoring=enabled | ✅ |
| `k8s/configmap.yaml` | Configurações da aplicação | ✅ |
| `k8s/secrets.yaml` | Secrets (valores fake — substituir em prod) | ✅ |
| `k8s/storage.yaml` | PV + PVC para PostgreSQL (10Gi) | ✅ |
| `k8s/deployment.yaml` | 2 réplicas, probes, resources, anti-affinity | ✅ |
| `k8s/service.yaml` | LoadBalancer 80→8000, sessionAffinity | ✅ |
| `k8s/hpa.yaml` | HPA min:2 max:10, CPU 70% / Mem 80% | ✅ |
| `k8s/statefulset-postgres.yaml` | PostgreSQL 15 com PVC 20Gi | ✅ |
| `k8s/postgres-headless-service.yaml` | ClusterIP headless para StatefulSet | ✅ |
| `k8s/ingress.yaml` | Ingress nginx + TLS via cert-manager | ✅ |
| `scripts/deploy.sh` | Deploy completo com 14 steps | ✅ |
| `docs/INGRESS_SETUP.md` | Guia de setup nginx + SSL | ✅ |

## Deploy e Validação

```bash
# Editar image no deployment.yaml
sed -i 's/DOCKER_USERNAME/seu-usuario/g' k8s/deployment.yaml

# Deploy completo
export DOCKER_USERNAME=seu-usuario
bash scripts/deploy.sh production latest

# Verificar nós
kubectl get nodes

# Verificar pods (esperar 2+ Running)
kubectl get pods -n production -w

# Verificar HPA
kubectl get hpa -n production

# Verificar serviço e IP
kubectl get svc -n production

# Health check
curl http://<LOADBALANCER_IP>/health
```

## Recursos Kubernetes

| Recurso | Configuração |
|---|---|
| Deployment replicas | 2 inicial → 10 máximo (HPA) |
| CPU request/limit | 100m / 500m |
| Memory request/limit | 256Mi / 512Mi |
| Liveness probe | GET /health — 30s delay, 10s interval |
| Readiness probe | GET /ready — 10s delay, 5s interval |
| Rolling update | maxSurge:1, maxUnavailable:0 (zero downtime) |
| Security | runAsNonRoot, readOnlyRootFilesystem, no capabilities |
| Anti-affinity | Pods em nós diferentes |
| PostgreSQL storage | 20Gi PVC por pod |

## Próximos Passos — Fase 4
- [ ] Prometheus para coleta de métricas
- [ ] Grafana para dashboards
- [ ] Alertas via PrometheusRule
- [ ] Runbook de incidentes
