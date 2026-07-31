# FinFlow Local Lab Guide

> Step-by-step guide to deploy and learn with the FinFlow platform on your local machine.
> Follow this document like a hands-on lab — each section builds on the previous one.

---

## Prerequisites

You need these installed (check with the commands shown):

```bash
docker --version     # Docker Desktop 24+
kubectl version      # kubectl 1.28+
kind --version       # kind 0.20+
helm version         # Helm 3.12+
go version           # Go 1.21+
python3 --version    # Python 3.11+
```

---

## Lab 1: Create the Kubernetes Cluster

### WHAT
We're creating a local Kubernetes cluster using `kind` (Kubernetes in Docker). This simulates what GKE/EKS gives you in the cloud — but runs entirely on your laptop inside Docker containers.

### WHY
- You can't learn Kubernetes without a cluster to experiment on
- Kind is free and disposable — break it, delete it, recreate it
- Our config simulates a real production setup (multi-node, multi-zone)

### HOW

```bash
cd ~/Documents/cloud-engineer-moniepoint/finflow-platform

# Create the cluster (takes 2-3 minutes)
kind create cluster --config local-dev/kind-cluster.yaml
```

### WHAT THE CONFIG DOES

```yaml
# local-dev/kind-cluster.yaml

name: finflow              # Cluster name (shows in kubectl context as "kind-finflow")

nodes:
  - role: control-plane    # The "brain" — runs API server, scheduler, controller
    extraPortMappings:     # Expose ports on localhost for testing
      - containerPort: 80  # HTTP
      - containerPort: 443 # HTTPS

  - role: worker           # Worker node 1 — runs your application pods
    node-labels:
      topology.kubernetes.io/zone=zone-a   # Simulates Availability Zone A

  - role: worker           # Worker node 2 — runs your application pods
    node-labels:
      topology.kubernetes.io/zone=zone-b   # Simulates Availability Zone B
```

**Why 2 workers with zone labels?**
In production (GKE/EKS), your nodes are spread across availability zones. If one zone goes down, pods on the other zone keep serving traffic. We simulate this locally so you can practice topology spread constraints.

### VERIFY

```bash
# Check nodes are Ready
kubectl get nodes --context kind-finflow

# Expected output:
# NAME                    STATUS   ROLES           AGE   VERSION
# finflow-control-plane   Ready    control-plane   1m    v1.36.1
# finflow-worker          Ready    <none>          45s   v1.36.1
# finflow-worker2         Ready    <none>          45s   v1.36.1

# Check zone labels
kubectl get nodes --show-labels | grep zone
# finflow-worker  ... topology.kubernetes.io/zone=zone-a
# finflow-worker2 ... topology.kubernetes.io/zone=zone-b
```

### CLEAN UP (if you want to start over)
```bash
kind delete cluster --name finflow
```

---

## Lab 2: Build Docker Images

### WHAT
We're compiling our Go/Python microservices into Docker images — the same way a CI/CD pipeline (Jenkins) would do it in production.

### WHY
- Kubernetes runs containers, not source code
- Multi-stage builds keep images small and secure (no compiler tools in production)
- We use "distroless" base images — minimal attack surface

### HOW

```bash
cd ~/Documents/cloud-engineer-moniepoint/finflow-platform

# Build all 5 services
docker build -f docker/transaction-api.Dockerfile -t finflow/transaction-api:v1.0.0 .
docker build -f docker/payment-processor.Dockerfile -t finflow/payment-processor:v1.0.0 .
docker build -f docker/account-service.Dockerfile -t finflow/account-service:v1.0.0 .
docker build -f docker/fraud-detection.Dockerfile -t finflow/fraud-detection:v1.0.0 .
docker build -f docker/notification-service.Dockerfile -t finflow/notification-service:v1.0.0 .
```

**Note:** You MUST run `go mod tidy` in each Go service directory first:
```bash
cd services/transaction-api && go mod tidy && cd ../..
cd services/payment-processor && go mod tidy && cd ../..
cd services/account-service && go mod tidy && cd ../..
```

### WHAT HAPPENS DURING THE BUILD

```dockerfile
# docker/transaction-api.Dockerfile (simplified explanation)

# STAGE 1: Build (big image with compiler tools)
FROM golang:1.21-alpine AS builder
COPY services/transaction-api/ .
RUN go build -o /bin/transaction-api .    # Compile source into binary

# STAGE 2: Runtime (tiny image, no compiler)
FROM gcr.io/distroless/static:nonroot     # ~2MB base image, no shell, no tools
COPY --from=builder /bin/transaction-api   # Only the compiled binary
USER nonroot:nonroot                       # Never run as root
ENTRYPOINT ["/bin/transaction-api"]        # Start the app
```

**Why multi-stage?**
- Build stage: ~300MB (Go compiler, source code, dependencies)
- Runtime stage: ~10MB (just the binary + CA certificates)
- Attackers can't exploit a shell/tools that don't exist

### LOAD IMAGES INTO KIND

Kind uses its own image store (not Docker's). You must load images into the cluster:

```bash
kind load docker-image \
  finflow/transaction-api:v1.0.0 \
  finflow/payment-processor:v1.0.0 \
  finflow/account-service:v1.0.0 \
  finflow/fraud-detection:v1.0.0 \
  finflow/notification-service:v1.0.0 \
  --name finflow
```

**In production:** Images go to a registry (GCR, ECR, Docker Hub). Kubernetes pulls from there. Locally, we skip the registry and load directly.

### VERIFY

```bash
# Check images are loaded on kind nodes
docker exec finflow-worker crictl images | grep finflow
```

---

## Lab 3: Deploy Services to Kubernetes

### WHAT
We're deploying all 5 microservices into the cluster with proper namespace isolation, configuration, and secrets.

### WHY
- Namespaces isolate workloads (like separate folders)
- ConfigMaps store non-sensitive config (Kafka address, feature flags)
- Secrets store sensitive config (database passwords) — in production this comes from Vault
- Services provide stable DNS names for inter-service communication

### HOW

```bash
cd ~/Documents/cloud-engineer-moniepoint/finflow-platform

# Deploy everything (order matters: namespaces first, then config, then services)
kubectl apply -f local-dev/k8s/ --context kind-finflow
```

This single command applies 3 files in order (alphabetical):
1. `00-namespace.yaml` — Creates namespaces
2. `01-config.yaml` — Creates ConfigMap and Secrets
3. `02-services.yaml` — Creates Deployments and Services

### WHAT EACH FILE DOES

**00-namespace.yaml:**
```yaml
# Namespaces = isolated environments within the cluster
# Like having separate folders for different concerns
apiVersion: v1
kind: Namespace
metadata:
  name: finflow              # Application services live here
---
kind: Namespace
metadata:
  name: finflow-kafka        # Kafka cluster lives here (separate)
---
kind: Namespace
metadata:
  name: finflow-monitoring   # Prometheus/Grafana live here (separate)
```

**01-config.yaml:**
```yaml
# ConfigMap: Non-sensitive configuration shared across services
apiVersion: v1
kind: ConfigMap
metadata:
  name: finflow-config
data:
  kafka-bootstrap-servers: "finflow-kafka-bootstrap.finflow-kafka.svc.cluster.local:9092"
  # ↑ This is a Kubernetes DNS name. Format: <service>.<namespace>.svc.cluster.local

---
# Secret: Sensitive data (passwords). In production → Vault dynamic secrets.
apiVersion: v1
kind: Secret
metadata:
  name: finflow-db-credentials
stringData:
  host: "localhost"
  username: "finflow_app"
  password: "local-dev-only"     # NEVER use real passwords in manifests
```

**02-services.yaml (one service explained):**
```yaml
# Deployment: "Run 1 copy of transaction-api"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: transaction-api
  namespace: finflow
spec:
  replicas: 1                     # 1 pod locally (3+ in production)
  template:
    spec:
      containers:
        - name: transaction-api
          image: finflow/transaction-api:v1.0.0
          imagePullPolicy: Never   # ← Don't try to pull from registry (loaded locally)
          ports:
            - name: http
              containerPort: 8080  # ← App listens on this port
          env:
            - name: SERVICE_NAME
              value: "transaction-api"
          resources:
            requests:              # "I need at least this much"
              cpu: 50m             # 50 millicores (0.05 CPU)
              memory: 64Mi
            limits:                # "Never exceed this"
              cpu: 200m
              memory: 128Mi
          livenessProbe:           # "Is the app alive?"
            httpGet:
              path: /health
              port: http
          readinessProbe:          # "Is the app ready for traffic?"
            httpGet:
              path: /ready
              port: http
---
# Service: Stable DNS name + load balancing
apiVersion: v1
kind: Service
metadata:
  name: transaction-api    # Other pods call: http://transaction-api.finflow.svc.cluster.local
spec:
  ports:
    - port: 80             # External port (what callers use)
      targetPort: http     # Maps to container's port 8080
  selector:
    app: transaction-api   # Routes traffic to pods with this label
```

### VERIFY

```bash
# Check all pods are Running
kubectl get pods -n finflow --context kind-finflow

# Expected (all 1/1 Running):
# NAME                                    READY   STATUS    RESTARTS   AGE
# account-service-xxxxx                   1/1     Running   0          30s
# fraud-detection-xxxxx                   1/1     Running   0          30s
# notification-service-xxxxx              1/1     Running   0          30s
# payment-processor-xxxxx                 1/1     Running   0          30s
# transaction-api-xxxxx                   1/1     Running   0          30s

# Check services have endpoints
kubectl get svc -n finflow --context kind-finflow
kubectl get endpoints -n finflow --context kind-finflow
```

### TROUBLESHOOTING

If a pod is NOT running:
```bash
# See what's wrong
kubectl describe pod <pod-name> -n finflow --context kind-finflow

# Check logs
kubectl logs <pod-name> -n finflow --context kind-finflow

# Common issues:
# - ErrImagePull → Image not loaded into kind (re-run kind load)
# - CrashLoopBackOff → App is crashing (check logs)
# - Pending → Not enough resources (check resource limits)
```

---

## Lab 4: Test the Services

### WHAT
Verify services are working by calling their APIs from your local machine.

### WHY
- Confirms the full chain works: Docker image → Kubernetes → Pod → Application
- Same endpoints you'd hit from the Moniepoint mobile app (in production)

### HOW

**Method 1: Port-forward (access from localhost)**
```bash
# Forward local port 8080 → transaction-api service port 80
kubectl port-forward svc/transaction-api 8080:80 -n finflow --context kind-finflow

# In another terminal:
# Health check
curl http://localhost:8080/health
# {"status":"healthy"}

# Create a transaction
curl -X POST http://localhost:8080/api/v1/transactions \
  -H "Content-Type: application/json" \
  -d '{
    "sender_account": "acct-001",
    "receiver_account": "acct-002",
    "amount": 50000,
    "currency": "NGN",
    "type": "transfer",
    "description": "Salary payment"
  }'

# View Prometheus metrics
curl http://localhost:8080/metrics | grep finflow
```

**Method 2: Test inter-service communication (from inside the cluster)**
```bash
# Run a temporary curl pod inside the cluster
kubectl run test --rm -it --image=curlimages/curl -n finflow --context kind-finflow --restart=Never -- \
  curl -s http://transaction-api.finflow.svc.cluster.local/health

# This proves: Kubernetes DNS + Service discovery works
# "transaction-api" resolves to the pod's IP automatically
```

**Test other services:**
```bash
# Port-forward each service on different local ports
kubectl port-forward svc/account-service 8082:80 -n finflow --context kind-finflow &
kubectl port-forward svc/fraud-detection 8083:80 -n finflow --context kind-finflow &
kubectl port-forward svc/payment-processor 8081:80 -n finflow --context kind-finflow &

# Test account service
curl http://localhost:8082/api/v1/accounts

# Test fraud detection
curl -X POST http://localhost:8083/api/v1/score \
  -H "Content-Type: application/json" \
  -d '{
    "transaction_id": "txn-123",
    "sender_account": "acct-001",
    "receiver_account": "acct-002",
    "amount": 5000000,
    "currency": "NGN",
    "type": "transfer"
  }'

# Test payment processor
curl -X POST http://localhost:8081/api/v1/process \
  -H "Content-Type: application/json" \
  -d '{
    "transaction_id": "txn-123",
    "sender_account": "acct-001",
    "receiver_account": "acct-002",
    "amount": 50000,
    "currency": "NGN",
    "type": "transfer"
  }'

# Kill background port-forwards when done
kill %1 %2 %3 %4
```

---

## Lab 5: Break Things (Chaos Learning)

### WHAT
Intentionally break things to understand how Kubernetes handles failures.

### WHY
Senior engineers are expected to know what happens when things fail. You learn this by causing failures deliberately.

### EXERCISES

**Exercise 1: Kill a pod (self-healing)**
```bash
# See running pods
kubectl get pods -n finflow --context kind-finflow

# Delete a pod (simulate crash)
kubectl delete pod -l app=transaction-api -n finflow --context kind-finflow

# Watch Kubernetes recreate it automatically (within seconds)
kubectl get pods -n finflow -w --context kind-finflow
# The Deployment controller notices 0/1 replicas → creates a new pod

# Interview question: "What happens when a pod crashes in production?"
# Answer: Kubernetes detects via liveness probe failure or process exit,
#         terminates the pod, and the Deployment controller creates a replacement.
#         With multiple replicas, other pods serve traffic during recovery.
```

**Exercise 2: Scale up and down**
```bash
# Scale transaction-api to 3 replicas
kubectl scale deployment/transaction-api --replicas=3 -n finflow --context kind-finflow

# Watch pods spread across zones
kubectl get pods -n finflow -o wide --context kind-finflow
# Some on finflow-worker (zone-a), some on finflow-worker2 (zone-b)

# Scale back down
kubectl scale deployment/transaction-api --replicas=1 -n finflow --context kind-finflow
```

**Exercise 3: Check resource usage**
```bash
# See CPU/memory usage per pod
kubectl top pods -n finflow --context kind-finflow

# See per-node usage
kubectl top nodes --context kind-finflow
```

**Exercise 4: View logs**
```bash
# Stream live logs from transaction-api
kubectl logs -f deploy/transaction-api -n finflow --context kind-finflow

# In another terminal, make requests and watch logs appear:
curl -X POST http://localhost:8080/api/v1/transactions -H "Content-Type: application/json" \
  -d '{"sender_account":"acct-001","receiver_account":"acct-002","amount":1000,"currency":"NGN","type":"transfer"}'
```

---

## What's Next (Future Labs)

| Lab | Topic | What You'll Add |
|-----|-------|----------------|
| 6 | Kafka | Deploy Strimzi Kafka, produce/consume events between services |
| 7 | Prometheus + Grafana | Deploy monitoring, see real metrics dashboards |
| 8 | Istio | Install service mesh, enable mTLS, test canary deployments |
| 9 | ArgoCD | Install GitOps controller, deploy via git commits |
| 10 | Network Policies | Lock down service-to-service communication |

---

## Quick Reference Commands

```bash
# Cluster management
kind create cluster --config local-dev/kind-cluster.yaml
kind delete cluster --name finflow
kind load docker-image <image> --name finflow

# Deploy
kubectl apply -f local-dev/k8s/ --context kind-finflow

# Debug
kubectl get pods -n finflow --context kind-finflow
kubectl describe pod <name> -n finflow --context kind-finflow
kubectl logs <name> -n finflow --context kind-finflow
kubectl exec -it <name> -n finflow --context kind-finflow -- /bin/sh

# Test
kubectl port-forward svc/<service> <local-port>:80 -n finflow --context kind-finflow

# Clean slate
kubectl delete -f local-dev/k8s/ --context kind-finflow
kubectl apply -f local-dev/k8s/ --context kind-finflow
```
