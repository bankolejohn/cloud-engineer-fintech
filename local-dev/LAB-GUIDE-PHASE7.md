# Phase 7 Lab: Security (Vault + Network Policies)

> After this lab you'll understand secrets management and network-level access control — and be able to answer: "How do you handle secrets in Kubernetes?" and "How do you implement zero-trust networking?"

---

## What We Built

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  VAULT (vault namespace)                                                     │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ Secrets stored:                                                         │ │
│  │   secret/finflow/transaction-api    → db-username, db-password, api-key│ │
│  │   secret/finflow/payment-processor  → db-username, payment-gateway-key │ │
│  │   secret/finflow/fraud-detection    → db-username (read-only)          │ │
│  │   secret/finflow/notification-svc   → sendgrid-key, twilio-sid/token   │ │
│  │                                                                         │ │
│  │ Policies:                                                               │ │
│  │   finflow-transaction-api    → can ONLY read its own secrets + shared  │ │
│  │   finflow-payment-processor  → can ONLY read its own secrets + shared  │ │
│  │   finflow-fraud-detection    → can ONLY read its own (read-only DB)    │ │
│  │                                                                         │ │
│  │ K8s Auth:                                                               │ │
│  │   Pod with SA "transaction-api" in ns "finflow"                        │ │
│  │     → gets policy "finflow-transaction-api"                            │ │
│  │     → can read secret/finflow/transaction-api                          │ │
│  │     → CANNOT read secret/finflow/payment-processor                     │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  NETWORK POLICIES (finflow namespace)                                        │
│                                                                              │
│  default-deny-ingress:  Block all incoming traffic from other namespaces    │
│  allow-finflow-internal: Allow pods within finflow to talk to each other    │
│  allow-kafka-egress:    Allow traffic to Kafka brokers (port 9092)          │
│  allow-vault-egress:    Allow traffic to Vault (port 8200)                  │
│  allow-prometheus:      Allow Prometheus to scrape /metrics                  │
│  allow-istio:          Allow Istio control plane communication              │
│  allow-dns:            Allow DNS resolution (essential)                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 1: Vault Secrets Management

### Why Not Just Use Kubernetes Secrets?

```
K8s Secrets:                          Vault:
- Base64 encoded (NOT encrypted)     - Encrypted at rest
- Anyone with kubectl can read them  - Per-service policies (least privilege)
- No rotation (same password forever)- Dynamic secrets with TTL (auto-expire)
- No audit trail                     - Full audit log (who read what, when)
- Stored in etcd (single point)      - HA cluster with auto-unseal
```

### Lab Steps

#### Install Vault (Dev Mode)

```bash
# Add Helm repo
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Create namespace
kubectl create namespace vault --context kind-finflow

# Install Vault in dev mode
helm install vault hashicorp/vault \
  -f local-dev/helm-values/vault.yaml \
  -n vault --kube-context kind-finflow

# Wait for pod to be ready
kubectl wait --for=condition=ready pod/vault-0 \
  -n vault --context kind-finflow --timeout=120s
```

#### Store Secrets

```bash
# Connect to Vault pod and store secrets
kubectl exec vault-0 -n vault --context kind-finflow -- \
  vault kv put secret/finflow/transaction-api \
    db-username="txn_api_user" \
    db-password="dynamic-secret-simulated-abc123" \
    api-key="sk_live_finflow_txn_api_key_2024"

# Verify
kubectl exec vault-0 -n vault --context kind-finflow -- \
  vault kv get secret/finflow/transaction-api
```

#### Configure Kubernetes Auth

```bash
# Enable K8s auth (pods authenticate using their service account)
kubectl exec vault-0 -n vault --context kind-finflow -- \
  vault auth enable kubernetes

kubectl exec vault-0 -n vault --context kind-finflow -- \
  vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc.cluster.local:443"
```

#### Create Policies (Least Privilege)

```bash
# transaction-api can ONLY read its own secrets
kubectl exec vault-0 -n vault --context kind-finflow -- \
  vault policy write finflow-transaction-api - <<'EOF'
path "secret/data/finflow/shared" { capabilities = ["read"] }
path "secret/data/finflow/transaction-api" { capabilities = ["read"] }
EOF

# Bind: pods with service account "transaction-api" in namespace "finflow"
#        → get the policy "finflow-transaction-api"
kubectl exec vault-0 -n vault --context kind-finflow -- \
  vault write auth/kubernetes/role/transaction-api \
    bound_service_account_names=transaction-api \
    bound_service_account_namespaces=finflow \
    policies=finflow-transaction-api \
    ttl=1h
```

#### Test Access Control

```bash
# transaction-api can read its OWN secrets:
kubectl exec vault-0 -n vault --context kind-finflow -- \
  vault kv get secret/finflow/transaction-api
# → Shows db-username, db-password, api-key ✅

# But it CANNOT read payment-processor's secrets (different policy):
# (In production, this is enforced by the K8s auth role)
# The transaction-api pod would get "permission denied"
```

---

## Part 2: Network Policies

### The Zero-Trust Network Model

```
WITHOUT Network Policies:
  Any pod → can reach → any other pod (flat network)
  A compromised pod in the "default" namespace could call payment-processor
  
WITH Network Policies:
  default-deny blocks everything
  Explicit allow rules ONLY for legitimate traffic paths:
    finflow pods → finflow pods: ALLOWED (internal communication)
    finflow pods → kafka: ALLOWED (event streaming)
    prometheus → finflow pods: ALLOWED (metrics scraping)
    default namespace → finflow: BLOCKED ❌
    unknown pod → payment-processor: BLOCKED ❌
```

### Lab Steps

#### Apply Network Policies

```bash
kubectl apply -f local-dev/k8s/05-network-policies.yaml --context kind-finflow
```

#### Test: Internal Communication (Should Work)

```bash
# From inside the mesh (same namespace) — ALLOWED
kubectl exec deploy/transaction-api -n finflow --context kind-finflow -c istio-proxy -- \
  curl -s --max-time 5 http://payment-processor/health
# → {"status":"healthy"} ✅
```

#### Test: External Access (Should Be Blocked)

```bash
# From a different namespace — BLOCKED by default-deny-ingress
kubectl run attacker --rm -i --image=curlimages/curl:latest \
  -n default --context kind-finflow --restart=Never -- \
  curl -s --max-time 5 http://transaction-api.finflow.svc.cluster.local/health
# → Timeout / Connection refused ❌
```

#### Verify Policy List

```bash
kubectl get networkpolicies -n finflow --context kind-finflow
# NAME                      POD-SELECTOR   AGE
# default-deny-ingress      <none>         1m
# allow-dns                 <none>         1m
# allow-finflow-internal    <none>         1m
# allow-kafka-egress        <none>         1m
# allow-vault-egress        <none>         1m
# allow-prometheus-scrape   <none>         1m
# allow-istio               <none>         1m
```

---

## Key Security Layers (Defense in Depth)

```
Layer 1: Network Policies    → "Can this pod even REACH the other pod?" (network level)
Layer 2: Istio mTLS          → "Is the caller a legitimate mesh member?" (transport level)
Layer 3: Istio AuthzPolicy   → "Is this SERVICE allowed to call this ENDPOINT?" (application level)
Layer 4: Vault               → "Does this service have permission to read this SECRET?" (data level)

An attacker must bypass ALL FOUR layers to access sensitive data.
Each layer is independent — one failing doesn't compromise the others.
```

---

## Interview Questions You Can Now Answer

1. **"How do you manage secrets in Kubernetes?"**
   → Vault with Kubernetes auth. Each service has a service account. Vault maps service accounts to policies. Policies grant access to ONLY that service's secrets. Vault Agent sidecar injects secrets as files. No secrets in Git or K8s Secrets objects.

2. **"What are Network Policies and why do you need them?"**
   → Kubernetes-native firewall rules at the pod level. We use default-deny + explicit allow rules. Even with Istio mTLS, network policies provide defense-in-depth — a compromised pod in another namespace can't even establish a TCP connection to our services.

3. **"How do you implement zero-trust in Kubernetes?"**
   → Four layers: Network Policies (block unauthorized connections), Istio mTLS (encrypt + authenticate all traffic), Istio AuthorizationPolicies (per-service/per-method/per-path access control), Vault (per-service secret access with audit logging).

4. **"What happens when a secret needs to be rotated?"**
   → In dev mode: Update the secret in Vault, pods read it on next access. In production: Vault dynamic secrets auto-expire (1h TTL), new credentials generated automatically. No manual rotation needed.

---

## What's Running After This Lab

```
vault namespace:
  ✅ vault-0 (Vault server in dev mode, root token: "root")
  ✅ vault-agent-injector (ready to inject secrets into pods)
  ✅ Secrets stored: 5 paths (shared + 4 services)
  ✅ Policies: 4 per-service policies (least privilege)
  ✅ K8s auth: configured with roles

Network Policies applied (finflow namespace):
  ✅ default-deny-ingress (blocks traffic from other namespaces)
  ✅ allow-finflow-internal (services can talk to each other)
  ✅ allow-kafka-egress (services can reach Kafka)
  ✅ allow-vault-egress (services can reach Vault)
  ✅ allow-prometheus-scrape (monitoring works)
  ✅ allow-istio (service mesh communication)
  ✅ allow-dns (name resolution)
```

---

## Access Quick Reference

```bash
# Access Vault UI
kubectl port-forward svc/vault-ui 8200:8200 -n vault --context kind-finflow
# → http://localhost:8200 (token: root)

# Read a secret via CLI
kubectl exec vault-0 -n vault --context kind-finflow -- vault kv get secret/finflow/transaction-api

# List all secrets
kubectl exec vault-0 -n vault --context kind-finflow -- vault kv list secret/finflow/

# List network policies
kubectl get networkpolicies -n finflow --context kind-finflow
```
