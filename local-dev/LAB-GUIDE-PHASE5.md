# Phase 5 Lab: Istio Service Mesh

> After this lab you'll understand how Istio provides mTLS, traffic management, and resilience — and be able to answer: "How do you implement zero-downtime canary deployments?"

---

## What We Built

```
BEFORE Istio:                           AFTER Istio:
┌────────────────────────┐              ┌─────────────────────────────────────────┐
│ Pod                     │              │ Pod                                      │
│ ┌────────────────────┐ │              │ ┌────────────────────┐ ┌──────────────┐ │
│ │ transaction-api     │ │              │ │ transaction-api     │ │ Envoy Proxy  │ │
│ │ (plain HTTP)        │ │              │ │ (plain HTTP)        │ │ (sidecar)    │ │
│ └────────────────────┘ │              │ │                     │ │              │ │
└────────────────────────┘              │ │ Thinks nothing      │ │ Encrypts all │ │
                                        │ │ changed             │ │ traffic with │ │
Pod count: 1/1                          │ │                     │ │ mTLS         │ │
                                        │ └────────────────────┘ └──────────────┘ │
                                        └─────────────────────────────────────────┘
                                        Pod count: 2/2 (app + sidecar)
```

---

## What Istio Gives Us (Without Changing Application Code)

| Feature | What it does | How we'd do it WITHOUT Istio |
|---------|-------------|------------------------------|
| **mTLS** | Encrypts all traffic between services | Every developer implements TLS in their app |
| **Retries** | Retries failed requests automatically | Every developer writes retry logic |
| **Circuit Breaking** | Stops sending traffic to failing pods | Every developer implements circuit breakers |
| **Timeouts** | Enforces request timeouts | Every developer configures timeouts |
| **Canary Routing** | Split traffic between versions (90/10) | Build custom load balancer logic |
| **Observability** | Request metrics, traces, access logs | Every developer adds instrumentation |

**The key insight:** All of this happens in the Envoy sidecar proxy. Your application code is UNCHANGED.

---

## Lab Steps

### Step 1: Install Istio

```bash
# Install Istio with our local config
istioctl install -f local-dev/istio/istio-local.yaml --context kind-finflow -y

# Verify installation
istioctl verify-install --context kind-finflow
kubectl get pods -n istio-system --context kind-finflow
```

### Step 2: Enable Sidecar Injection

```bash
# Label the namespace (tells Istio to inject sidecars into all new pods)
kubectl label namespace finflow istio-injection=enabled --overwrite --context kind-finflow

# Restart all pods to get sidecars injected
kubectl rollout restart deployment -n finflow --context kind-finflow

# Wait and verify: should show 2/2 (app + sidecar)
kubectl get pods -n finflow --context kind-finflow
```

**IMPORTANT:** If pods show `ImagePullBackOff` for `istio/proxyv2`:
```bash
# Pull the image locally and load into kind
docker pull istio/proxyv2:1.30.3
kind load docker-image istio/proxyv2:1.30.3 --name finflow

# Delete stuck pods (Deployment will recreate them)
kubectl delete pod -l app=<stuck-service> -n finflow --context kind-finflow
```

### Step 3: Verify mTLS is Working

```bash
# Check all proxies are connected to istiod
istioctl proxy-status --context kind-finflow

# Test: Call from INSIDE the mesh (works — has sidecar)
kubectl exec deploy/transaction-api -n finflow --context kind-finflow -c istio-proxy -- \
  curl -s http://payment-processor/health
# → {"status":"healthy"}

# Test: Call from OUTSIDE the mesh (may be blocked — no sidecar)
kubectl run no-mesh --rm -i --image=curlimages/curl:latest \
  -n default --context kind-finflow --restart=Never -- \
  curl -s --max-time 5 http://payment-processor.finflow.svc.cluster.local/health
# → Timeout or connection refused (mTLS rejects non-mesh traffic)
```

**Why this matters:** An attacker who compromises a pod in a different namespace (without Istio sidecar) CANNOT call your services. The mesh only accepts mTLS connections from other mesh members.

### Step 4: Apply Traffic Management Rules

```bash
kubectl apply -f local-dev/istio/traffic-management.yaml --context kind-finflow

# Verify
istioctl analyze -n finflow --context kind-finflow
# Warning about v2 subset having no pods is EXPECTED (we haven't deployed v2)
```

### Step 5: Verify Circuit Breaker & Retries

```bash
# Check Envoy proxy configuration for transaction-api
istioctl proxy-config cluster deploy/transaction-api -n finflow --context kind-finflow | grep payment

# Check route configuration (shows retries and timeouts)
istioctl proxy-config route deploy/transaction-api -n finflow --context kind-finflow | head -20
```

---

## Understanding What Was Configured

### DestinationRule (Circuit Breaking)

```yaml
spec:
  host: payment-processor
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 3      # If a pod returns 3 errors in a row...
      interval: 5s                 # ...checked every 5 seconds...
      baseEjectionTime: 30s        # ...remove it from rotation for 30 seconds
      maxEjectionPercent: 30       # Never remove more than 30% of pods
```

**Plain English:** "If a payment-processor pod returns 3 errors in a row, Istio stops sending it traffic for 30 seconds. Other healthy pods handle requests. After 30s, the pod is added back. If it fails again, ejection time doubles."

### VirtualService (Retries + Timeouts)

```yaml
spec:
  hosts: [payment-processor]
  http:
    - route:
        - destination: {host: payment-processor, subset: v1}
          weight: 100
      retries:
        attempts: 1              # Only 1 retry for payments
        perTryTimeout: 10s       # Each attempt has 10s max
        retryOn: gateway-error,connect-failure  # Only retry on infra errors
      timeout: 30s               # Overall timeout: 30 seconds
```

**Why only 1 retry for payments?** Payments are NOT idempotent by default. If you retry a "debit ₦50,000" request and the first one actually went through (but response was lost), you'd debit twice. So we only retry on connection failures (where the request definitely didn't reach the server).

### Canary Setup (Ready for v2)

```yaml
subsets:
  - name: v1
    labels: {version: v1}   # Current pods
  - name: v2
    labels: {version: v2}   # Future canary pods
```

**To do a canary deployment:**
1. Deploy v2 pods with label `version: v2`
2. Change VirtualService weight: `v1: 90, v2: 10`
3. Monitor error rate for v2 in Grafana
4. If OK → `v1: 50, v2: 50` → then `v1: 0, v2: 100`
5. If bad → `v1: 100, v2: 0` (instant rollback)

---

## Lab Exercises

### Exercise 1: Prove mTLS Works

```bash
# FROM mesh (should work):
kubectl exec deploy/transaction-api -n finflow --context kind-finflow -c istio-proxy -- \
  curl -s http://account-service/api/v1/accounts

# FROM outside mesh (should fail/timeout):
kubectl run outsider --rm -i --image=curlimages/curl:latest \
  -n default --context kind-finflow --restart=Never -- \
  curl -s --max-time 5 http://account-service.finflow.svc.cluster.local/health
```

### Exercise 2: View Envoy Access Logs

```bash
# Make a request
kubectl exec deploy/transaction-api -n finflow --context kind-finflow -c istio-proxy -- \
  curl -s http://payment-processor/health

# Check the access log (in the destination pod's sidecar)
kubectl logs deploy/payment-processor -n finflow --context kind-finflow -c istio-proxy | tail -5
```

You'll see a log line showing: source IP, destination, response code, latency — all without any application logging code.

### Exercise 3: Test Timeout Behavior

```bash
# The fraud-detection VirtualService has a 5s timeout
# If fraud-detection were slow (>5s), the request would be terminated
kubectl exec deploy/transaction-api -n finflow --context kind-finflow -c istio-proxy -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://fraud-detection/health
# Should return: 200 in <1 second (healthy)
```

---

## How Canary Deployment Works (Step by Step)

```
DAY 1: Deploy v2 alongside v1
─────────────────────────────
kubectl apply -f deployment-v2.yaml   # New pods with label version=v2
# Result: v1 pods (100% traffic) + v2 pods (0% traffic)

DAY 1: Route 10% to v2
─────────────────────────
# Edit VirtualService:
route:
  - destination: {host: transaction-api, subset: v1}
    weight: 90
  - destination: {host: transaction-api, subset: v2}
    weight: 10

# Watch Grafana for 30 minutes. Compare v1 vs v2 error rates.

DAY 2: If v2 is healthy → increase to 50%
──────────────────────────────────────────
route:
  - destination: {host: transaction-api, subset: v1}
    weight: 50
  - destination: {host: transaction-api, subset: v2}
    weight: 50

DAY 3: Full rollout
────────────────────
route:
  - destination: {host: transaction-api, subset: v2}
    weight: 100

# Then remove v1 pods. v2 is now the stable version.

ROLLBACK (at any point):
────────────────────────
route:
  - destination: {host: transaction-api, subset: v1}
    weight: 100
# Instant. No redeployment. Just a routing change.
```

---

## Interview Questions You Can Now Answer

1. **"How does Istio provide security without changing application code?"**
   → Envoy sidecar injected into every pod intercepts all traffic. Automatically negotiates mTLS certificates (issued by istiod, rotated every 24h). App sends plain HTTP internally — sidecar encrypts it on the wire.

2. **"How do you implement canary deployments?"**
   → Deploy v2 pods with a different version label. Istio VirtualService routes a percentage of traffic to v2 (10% → 50% → 100%). Monitor error rate in Grafana. Rollback = change the weight back to 100% v1. Instant, no redeployment.

3. **"What is a circuit breaker and why do you need one?"**
   → DestinationRule outlierDetection. If a pod returns 3 consecutive errors, Istio ejects it from the load balancer pool for 30 seconds. Prevents a broken pod from handling more requests and causing cascading failures.

4. **"How do you handle timeouts and retries?"**
   → VirtualService defines per-route timeout and retry policy. Different for each service: fraud-detection gets 5s timeout (should be fast), payment-processor gets 30s (payment gateways are slow). Retries only on infrastructure errors, NOT on business logic failures.

5. **"What happens if you need to inspect traffic between services?"**
   → Envoy access logs (configured with accessLogFile: /dev/stdout). Every request/response is logged with source, destination, status code, latency — without any application instrumentation.

---

## What's Running After This Lab

```
istio-system namespace:
  ✅ istiod (control plane — distributes config to all sidecars)
  ✅ istio-ingressgateway (entry point for external traffic)

finflow namespace (all pods now have 2/2 containers):
  ✅ transaction-api (app + envoy sidecar)
  ✅ payment-processor (app + envoy sidecar)
  ✅ account-service (app + envoy sidecar)
  ✅ fraud-detection (app + envoy sidecar)
  ✅ notification-service (app + envoy sidecar)

Traffic policies active:
  ✅ mTLS (auto-enabled for all mesh traffic)
  ✅ Circuit breakers (per-service outlier detection)
  ✅ Retries (with appropriate limits per service)
  ✅ Timeouts (5s fraud, 30s payments, 10s others)
  ✅ Canary subsets defined (ready for v2 deployment)
```
