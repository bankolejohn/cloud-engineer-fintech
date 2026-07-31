# Istio Service Mesh — Deep Dive

> How Istio provides security, traffic management, and observability without changing application code.

---

## What Istio Does (One Line)

An infrastructure layer that handles service-to-service communication — encryption, routing, retries, observability — by injecting a sidecar proxy into every pod.

---

## The Sidecar Pattern

```
WITHOUT Istio:
┌─────────────────────┐
│ Pod                  │
│ ┌─────────────────┐ │
│ │ your-app        │ │
│ └─────────────────┘ │
└─────────────────────┘

WITH Istio:
┌─────────────────────────────────────────┐
│ Pod                                      │
│ ┌─────────────────┐  ┌───────────────┐ │
│ │ your-app        │  │ Envoy Proxy   │ │
│ │ (unchanged)     │  │ (sidecar)     │ │
│ │                 │  │               │ │
│ │ Sends HTTP to   │  │ Intercepts    │ │
│ │ other services  │  │ ALL traffic   │ │
│ │ as normal       │  │ in and out    │ │
│ └─────────────────┘  └───────────────┘ │
└─────────────────────────────────────────┘

Your app doesn't know the sidecar exists.
The sidecar encrypts, retries, routes, and measures — transparently.
```

---

## 5 Core Istio Resources

### 1. Gateway — The Front Door
Accepts external traffic. Terminates TLS. Routes into the mesh.

```yaml
spec:
  servers:
    - port: {number: 443, protocol: HTTPS}
      hosts: ["api.finflow.io"]
      tls: {mode: SIMPLE, credentialName: finflow-tls-cert}
```

### 2. VirtualService — Routing Rules
Decides WHERE traffic goes. Enables canary deployments.

```yaml
# 90% to stable version, 10% to canary
route:
  - destination: {host: transaction-api, subset: v1}
    weight: 90
  - destination: {host: transaction-api, subset: v2}
    weight: 10
```

### 3. DestinationRule — HOW to Talk to Backends
Load balancing, circuit breaking, connection limits.

```yaml
# If a pod returns 3 consecutive 5xx errors, remove it for 30 seconds
outlierDetection:
  consecutive5xxErrors: 3
  interval: 5s
  baseEjectionTime: 30s
  maxEjectionPercent: 30
```

### 4. PeerAuthentication — Encrypt Everything (mTLS)
```yaml
spec:
  mtls:
    mode: STRICT   # ALL traffic must be mTLS encrypted
```

Both sides verify each other's identity. Automatic certificate rotation.
Your app does plain HTTP — the sidecar handles encryption transparently.

### 5. AuthorizationPolicy — Who Can Call Whom (Zero Trust)
```yaml
# Default: DENY ALL
spec: {}

# Then explicitly allow:
# "Only transaction-api can POST to /api/v1/process on payment-processor"
rules:
  - from: [{source: {principals: ["cluster.local/ns/finflow/sa/transaction-api"]}}]
    to: [{operation: {methods: ["POST"], paths: ["/api/v1/process"]}}]
```

---

## Traffic Flow (Full Path)

```
Internet → Istio Ingress Gateway
         → Gateway (TLS termination, host matching)
         → VirtualService (routing: which version? what weight?)
         → DestinationRule (load balancing algorithm, circuit breaker check)
         → AuthorizationPolicy (is caller allowed?)
         → Envoy Sidecar (decrypt mTLS, deliver to app)
         → Your application container
```

---

## Circuit Breaker Explained

```
Normal:  Request → Pod-1 ✅ → Pod-2 ✅ → Pod-3 ✅

Pod-2 starts failing:
  Request → Pod-2 ❌ 500
  Request → Pod-2 ❌ 500
  Request → Pod-2 ❌ 500  ← 3 consecutive errors!

Circuit TRIPS:
  Pod-2 EJECTED for 30 seconds. No traffic.
  Request → Pod-1 ✅
  Request → Pod-3 ✅
  (Customers never notice the bad pod)

After 30s: Pod-2 added back. If it fails again → ejected longer.
```

---

## Canary Deployment Flow

```
Deploy new version (v2):
  1. weight: v1=100, v2=0 (only v1 serves traffic)
  2. weight: v1=90, v2=10 (10% of users test v2)
  3. Monitor error rate for v2 via Prometheus
  4. If error rate OK → v1=50, v2=50
  5. If still OK → v1=0, v2=100 (full rollout)
  6. If errors spike at any step → v2=0 (instant rollback)
```

---

## Fault Injection (Chaos Testing)

Intentionally break things in staging to test resilience:

```yaml
fault:
  delay:
    percentage: {value: 10.0}    # 10% of requests delayed 5s
    fixedDelay: 5s
  abort:
    percentage: {value: 5.0}     # 5% get HTTP 503
    httpStatus: 503
```

Apply this YAML, watch dashboards, confirm circuit breakers work, delete it.

---

## Multi-Cluster Mesh

```
GCP Cluster ←── East-West Gateway ──→ AWS Cluster
    │              (VPN tunnel)              │
    │                                       │
    │  Locality-aware load balancing:       │
    │  "Prefer local cluster.              │
    │   Only send to AWS if GCP is DOWN."  │
```

---

## Key Files in This Repo

```
istio/istio-operator.yaml                    → Installation config
istio/traffic/gateway.yaml                   → Entry point
istio/traffic/virtual-services.yaml          → Routing (canary, A/B)
istio/traffic/destination-rules.yaml         → Circuit breaking, load balancing
istio/security/peer-authentication.yaml      → mTLS (strict)
istio/security/authorization-policies.yaml   → Zero-trust access control
istio/security/request-authentication.yaml   → JWT validation
istio/resilience/circuit-breaker.yaml        → Per-service circuit breaking
istio/resilience/fault-injection.yaml        → Chaos testing configs
istio/resilience/retry-timeout.yaml          → Retry policies
istio/multi-cluster/                         → Cross-cloud mesh setup
istio/observability/telemetry.yaml           → Metrics, tracing config
```
