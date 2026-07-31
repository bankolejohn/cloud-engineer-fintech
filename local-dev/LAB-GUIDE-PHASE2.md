# Phase 2 Lab: Observability (Prometheus + Grafana)

> After completing this lab, you'll understand how production monitoring works and be able to answer: "How do you monitor services in Kubernetes?"

---

## What We're Building

```
┌─────────────────────────────────────────────────────────────────────┐
│  finflow-monitoring namespace                                        │
│                                                                       │
│  ┌──────────────┐    ┌───────────┐    ┌──────────────────────────┐  │
│  │ Prometheus    │    │ Grafana   │    │ AlertManager             │  │
│  │              │    │           │    │                          │  │
│  │ Scrapes      │───▶│ Visualizes│    │ Routes alerts to         │  │
│  │ /metrics     │    │ metrics   │    │ Slack/PagerDuty/Email   │  │
│  │ every 15s    │    │ as graphs │    │                          │  │
│  └──────┬───────┘    └───────────┘    └──────────────────────────┘  │
│         │                                                            │
└─────────┼────────────────────────────────────────────────────────────┘
          │ scrapes
          ▼
┌─────────────────────────────────────────────────────────────────────┐
│  finflow namespace                                                    │
│                                                                       │
│  transaction-api ──── /metrics (exposes request count, latency)       │
│  payment-processor ── /metrics (exposes payment success/failure)      │
│  fraud-detection ──── /metrics (exposes fraud scores, processing time)│
│  account-service ──── /metrics (exposes account operations)           │
│  notification-svc ─── /metrics (exposes notifications sent/failed)    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Why Observability Matters (Interview Context)

At Moniepoint, if transactions are failing:
- **Without monitoring:** You find out when customers call support. Could be hours.
- **With monitoring:** AlertManager pages you within 2 minutes. Grafana shows EXACTLY which service started failing and when.

The **three pillars of observability:**
| Pillar | Tool | Question it answers |
|--------|------|-------------------|
| Metrics | Prometheus + Grafana | "How is the system performing RIGHT NOW?" |
| Logs | Loki (Phase 3+) | "What happened? Show me the error message." |
| Traces | Jaeger (Phase 5+) | "Where did this request spend time across services?" |

---

## Lab Steps

### Step 1: Install the Monitoring Stack

```bash
# Add Helm repo (one time)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack with our local values
helm install monitoring prometheus-community/kube-prometheus-stack \
  -f local-dev/helm-values/prometheus-stack.yaml \
  -n finflow-monitoring \
  --kube-context kind-finflow
```

**What this installs:**
| Component | What it does |
|-----------|-------------|
| Prometheus | Scrapes /metrics endpoints every 15s, stores time-series data |
| Grafana | Web UI for visualizing metrics as dashboards |
| AlertManager | Evaluates alert rules, routes notifications |
| Node Exporter | Exposes CPU/memory/disk metrics from each node |
| Kube-State-Metrics | Exposes Kubernetes object state (pod count, deployment status) |
| Prometheus Operator | Watches for ServiceMonitor/PrometheusRule CRDs |

### Step 2: Create the ServiceMonitor

```bash
kubectl apply -f local-dev/k8s/03-service-monitor.yaml --context kind-finflow
```

**What this does:**
```yaml
# "Hey Prometheus, scrape ALL services in the finflow namespace on port 'http' at path /metrics"
spec:
  namespaceSelector:
    matchNames: [finflow]       # Look in this namespace
  endpoints:
    - port: http                # Scrape this port name
      path: /metrics            # At this path
      interval: 15s             # Every 15 seconds
```

**Why ServiceMonitor instead of editing prometheus.yml?**
In production you have 50+ services. You can't manually edit Prometheus config for each one. ServiceMonitor is declarative — add a new service, add a ServiceMonitor, Prometheus auto-discovers it.

### Step 3: Verify Prometheus is Scraping

```bash
# Port-forward to access Prometheus UI
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 \
  -n finflow-monitoring --context kind-finflow

# Open in browser: http://localhost:9090
# Go to Status → Targets
# You should see finflow services listed as "UP"
```

**Or via API:**
```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep "health"
```

### Step 4: Access Grafana

```bash
# Port-forward to Grafana
kubectl port-forward svc/monitoring-grafana 3000:80 \
  -n finflow-monitoring --context kind-finflow

# Open in browser: http://localhost:3000
# Login: admin / finflow-local
```

### Step 5: Query Metrics (PromQL)

In Prometheus UI (http://localhost:9090), try these queries:

```promql
# Total HTTP requests across all services
finflow_http_requests_total

# Request rate (requests per second) for transaction-api
rate(finflow_http_requests_total{service="transaction-api"}[5m])

# 99th percentile latency
histogram_quantile(0.99, rate(finflow_http_request_duration_seconds_bucket[5m]))

# Payment success rate (percentage)
sum(rate(finflow_payments_processed_total{status="completed"}[5m]))
/ sum(rate(finflow_payments_processed_total[5m])) * 100

# Active fraud alerts
finflow_active_fraud_alerts
```

### Step 6: Generate Traffic (to see metrics move)

```bash
# Port-forward transaction-api
kubectl port-forward svc/transaction-api 8080:80 -n finflow --context kind-finflow &

# Send 50 transactions in a loop
for i in $(seq 1 50); do
  curl -s -X POST http://localhost:8080/api/v1/transactions \
    -H "Content-Type: application/json" \
    -d "{\"sender_account\":\"acct-001\",\"receiver_account\":\"acct-002\",\"amount\":$((RANDOM % 100000)),\"currency\":\"NGN\",\"type\":\"transfer\"}" > /dev/null
  sleep 0.5
done

echo "Done! Check Grafana — you should see a spike in request rate."
```

Now go to Grafana → Explore → select Prometheus data source → run:
```promql
rate(finflow_http_requests_total[1m])
```
You'll see the request rate spike.

---

## Key Concepts Explained

### How Prometheus Scraping Works

```
Every 15 seconds:
  Prometheus → HTTP GET http://transaction-api-pod:8080/metrics

  Response (text format):
  # HELP finflow_http_requests_total Total number of HTTP requests
  # TYPE finflow_http_requests_total counter
  finflow_http_requests_total{method="POST",endpoint="/api/v1/transactions",status="201"} 47
  finflow_http_requests_total{method="GET",endpoint="/health",status="200"} 2048
  
  # HELP finflow_http_request_duration_seconds HTTP request duration
  # TYPE finflow_http_request_duration_seconds histogram
  finflow_http_request_duration_seconds_bucket{method="POST",le="0.005"} 42
  finflow_http_request_duration_seconds_bucket{method="POST",le="0.01"} 45
  finflow_http_request_duration_seconds_bucket{method="POST",le="+Inf"} 47

Prometheus stores these values with timestamps.
Grafana queries them to render graphs.
```

### Metric Types

| Type | What it is | Example |
|------|-----------|---------|
| Counter | Only goes up (total count) | `finflow_http_requests_total` = 1523 |
| Gauge | Goes up AND down (current value) | `finflow_active_fraud_alerts` = 3 |
| Histogram | Distribution of values (latency buckets) | `finflow_http_request_duration_seconds` |

### The RED Method (What to monitor for every service)

| Letter | Metric | PromQL |
|--------|--------|--------|
| **R**ate | Requests per second | `rate(finflow_http_requests_total[5m])` |
| **E**rrors | Error rate (% of 5xx) | `rate(requests{status=~"5.."}[5m]) / rate(requests[5m])` |
| **D**uration | Latency (P50, P95, P99) | `histogram_quantile(0.99, rate(duration_bucket[5m]))` |

---

## Lab Exercises

### Exercise 1: Build a Grafana Dashboard
1. Open Grafana (http://localhost:3000)
2. Click "+" → "New Dashboard"
3. Add a panel with query: `rate(finflow_http_requests_total[1m])`
4. Add another panel: `histogram_quantile(0.99, rate(finflow_http_request_duration_seconds_bucket[1m]))`
5. Add a gauge: payment success rate

### Exercise 2: Trigger an Alert
1. Kill the transaction-api pod: `kubectl delete pod -l app=transaction-api -n finflow`
2. Watch Prometheus: the target goes "down"
3. Check AlertManager: `kubectl port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093 -n finflow-monitoring`
4. Open http://localhost:9093 — see the firing alert
5. K8s recreates the pod → target comes back "up" → alert resolves

### Exercise 3: Query like a Senior Engineer
Practice these PromQL queries in Prometheus UI:
```promql
# "Show me the top 3 services by request rate"
topk(3, sum(rate(finflow_http_requests_total[5m])) by (service))

# "Show me error rate per service"
sum(rate(finflow_http_requests_total{status=~"5.."}[5m])) by (service)
/ sum(rate(finflow_http_requests_total[5m])) by (service)

# "Is any pod using more than 80% of its memory limit?"
container_memory_usage_bytes{namespace="finflow"}
/ container_spec_memory_limit_bytes{namespace="finflow"} > 0.8
```

---

## Interview Questions You Can Now Answer

1. **"How do you monitor services in Kubernetes?"**
   → Prometheus scrapes /metrics endpoints via ServiceMonitor CRDs. Services expose metrics (counters, histograms, gauges). Grafana visualizes them. AlertManager routes alerts when thresholds are breached.

2. **"What is PromQL?"**
   → Prometheus Query Language. Used to query time-series data. Key functions: `rate()` for per-second rate, `histogram_quantile()` for percentiles, `sum() by (label)` for aggregation.

3. **"What metrics do you monitor for a payment service?"**
   → RED method: Request Rate (transactions/sec), Error Rate (% of 5xx responses), Duration (P99 latency). Plus business metrics: payment success rate, fraud detection scores, consumer lag.

4. **"How does service discovery work for Prometheus?"**
   → Prometheus Operator watches ServiceMonitor CRDs. When you create one, the operator auto-configures Prometheus to scrape the matching services. No manual config editing.

---

## What's Running After This Lab

```
finflow-monitoring namespace:
  ✅ Prometheus (scraping 5 FinFlow services + K8s metrics)
  ✅ Grafana (accessible at localhost:3000)
  ✅ AlertManager (evaluating alert rules)
  ✅ Node Exporter × 3 (system metrics per node)
  ✅ Kube-State-Metrics (K8s object metrics)
  ✅ ServiceMonitor (auto-discovers FinFlow services)
```

---

## Access Quick Reference

```bash
# Prometheus UI
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n finflow-monitoring --context kind-finflow
# → http://localhost:9090

# Grafana
kubectl port-forward svc/monitoring-grafana 3000:80 -n finflow-monitoring --context kind-finflow
# → http://localhost:3000 (admin / finflow-local)

# AlertManager
kubectl port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093 -n finflow-monitoring --context kind-finflow
# → http://localhost:9093
```
