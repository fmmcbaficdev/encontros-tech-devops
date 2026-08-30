# Runbook — Encontros Tech

> Guia de resposta a incidentes para o time de operações.

---

## Contatos

| Papel | Contato | Horário |
|---|---|---|
| Tech Lead | @tech-lead (Slack) | 24/7 |
| On-call | #oncall-devops (Slack) | 24/7 |
| Escalation | @engineering-manager | Business hours |

**Escalation Policy:**
1. On-call engineer (15 min)
2. Tech Lead (30 min)
3. Engineering Manager (60 min)

---

## 1. APP POD — CrashLoopBackOff

**Sintoma:** Alert `PodCrashLoopBackOff` ou pod status = `CrashLoopBackOff`

**Diagnóstico:**
```bash
kubectl get pods -n production
kubectl logs <pod-name> -n production --previous
kubectl describe pod <pod-name> -n production
kubectl get events -n production --sort-by='.lastTimestamp' | tail -20
```

**Ação:**
```bash
# Rollback imediato
kubectl rollout undo deployment/encontros-tech -n production
kubectl rollout status deployment/encontros-tech -n production

# Verificar versão anterior
kubectl rollout history deployment/encontros-tech -n production
```

---

## 2. HIGH LATENCY

**Sintoma:** Alert `HighLatency` — P95 > 1s

**Diagnóstico:**
```bash
# Ver conexões ativas
kubectl exec deployment/encontros-tech -n production -- ss -s

# Ver logs de requests lentos
kubectl logs deployment/encontros-tech -n production --since=5m | grep -i "slow\|timeout\|error"

# Verificar postgres
kubectl exec statefulset/postgres -n production -- \
  psql -U techuser -d encontros_tech -c "SELECT count(*) FROM pg_stat_activity;"
```

**Ação:**
```bash
# Escalar manualmente (HPA fará o mesmo automaticamente)
kubectl scale deployment/encontros-tech --replicas=5 -n production

# Verificar HPA
kubectl get hpa -n production -w
```

---

## 3. HIGH ERROR RATE

**Sintoma:** Alert `HighErrorRate` — 5xx > 1%

**Diagnóstico:**
```bash
kubectl logs deployment/encontros-tech -n production --since=10m | grep "500\|ERROR"
kubectl get events -n production
kubectl describe deployment encontros-tech -n production
```

**Ação:**
```bash
# Se último deploy causou o problema:
kubectl rollout undo deployment/encontros-tech -n production

# Verificar qual versão está rodando
kubectl get deployment encontros-tech -n production \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

---

## 4. OUT OF DISK SPACE

**Sintoma:** Alert `LowDiskSpace` ou PVC usage > 85%

**Diagnóstico:**
```bash
kubectl get pvc -n production
kubectl exec statefulset/postgres -n production -- df -h /var/lib/postgresql/data
```

**Ação:**
```bash
# Expandir PVC (requer StorageClass com allowVolumeExpansion: true)
kubectl patch pvc postgres-data-postgres-0 -n production \
  -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'

# Verificar expansão
kubectl get pvc -n production -w
```

---

## 5. DATABASE CONNECTION REFUSED

**Sintoma:** App logs com `could not connect to server` ou `connection refused`

**Diagnóstico:**
```bash
kubectl get pods -n production -l app=postgres
kubectl logs statefulset/postgres -n production
kubectl describe statefulset/postgres -n production
kubectl get pvc -n production
```

**Ação:**
```bash
# Reiniciar postgres se necessário
kubectl rollout restart statefulset/postgres -n production
kubectl rollout status statefulset/postgres -n production

# Verificar se app reconecta
kubectl rollout restart deployment/encontros-tech -n production
```

---

## 6. UNABLE TO PULL IMAGE

**Sintoma:** Pod status = `ImagePullBackOff` ou `ErrImagePull`

**Diagnóstico:**
```bash
kubectl describe pod <pod-name> -n production | grep -A5 "Events:"
kubectl get events -n production | grep ImagePull
```

**Ação:**
```bash
# Verificar se imagem existe no registry
docker manifest inspect docker.io/SEU_USUARIO/encontros-tech-api:TAG

# Recriar secret de registry (se credenciais expiraram)
kubectl create secret docker-registry regcred \
  --docker-username=SEU_USUARIO \
  --docker-password=SEU_TOKEN \
  --namespace=production \
  --dry-run=client -o yaml | kubectl apply -f -

# Recriar pod
kubectl rollout restart deployment/encontros-tech -n production
```

---

## Template de Comunicação (Incidente)

```
[INCIDENTE] Encontros Tech API — <SEVERIDADE>

Início: <HH:MM UTC>
Status: Investigando / Mitigado / Resolvido

Impacto: <descrição do impacto para usuários>

Causa raiz: <em investigação / confirmada: descrição>

Ações tomadas:
- <ação 1>
- <ação 2>

Próximos passos:
- <ação corretiva>

Engineer: <nome>
```
