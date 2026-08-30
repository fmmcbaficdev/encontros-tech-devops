# Ingress Setup — Encontros Tech

## 1. Instalar nginx-ingress Controller

```bash
# Via Helm (recomendado)
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=2

# Verificar instalação
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

## 2. Instalar cert-manager (SSL automático)

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

# Aguardar pods
kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=60s

# Criar ClusterIssuer (Let's Encrypt)
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: seu@email.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
```

## 3. Configurar DNS

Após instalar o ingress, obtenha o IP do LoadBalancer:

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
# Copie o EXTERNAL-IP
```

Configure o DNS do seu domínio:
```
encontros-tech.example.com  A  <EXTERNAL-IP>
```

## 4. Aplicar Ingress

```bash
# Edite k8s/ingress.yaml e troque example.com pelo seu domínio
kubectl apply -f k8s/ingress.yaml -n production

# Verificar
kubectl get ingress -n production
kubectl describe ingress encontros-tech -n production
```

## 5. Verificar certificado SSL

```bash
# Aguardar emissão (1-2 min)
kubectl get certificate -n production

# Testar HTTPS
curl https://encontros-tech.example.com/health
```
