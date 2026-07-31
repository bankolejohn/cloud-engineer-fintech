# Phase 4 Lab: Service-to-Service Communication

> After this lab you'll understand how microservices communicate in a fintech platform — both synchronously (HTTP) and asynchronously (Kafka).

---

## What We're Proving

This phase verifies that the **platform** (which YOU built) correctly enables service communication:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  The Platform Engineer's job is DONE when:                                   │
│                                                                              │
│  ✅ Services can reach each other via Kubernetes DNS                        │
│  ✅ Services can reach Kafka across namespaces                              │
│  ✅ ConfigMaps contain correct addresses                                    │
│  ✅ Network connectivity works (no firewall blocking)                       │
│  ✅ The full transaction flow works end-to-end                              │
│                                                                              │
│  The Backend Engineer's job is to:                                           │
│  - Write the actual produce/consume logic in their application code         │
│  - Define event schemas                                                      │
│  - Handle retries, DLQ, idempotency                                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Your Role vs Backend's Role (Critical Understanding)

```
Platform Engineer (YOU):                Backend Developer (THEM):
─────────────────────────               ──────────────────────────────
Creates Kafka cluster                   Writes producer code in Go/Python
Creates topics with correct config      Decides what events to publish
Creates KafkaUser with ACLs             Writes consumer code
Ensures DNS resolution works            Handles event processing logic
Ensures cross-namespace networking      Implements retry/DLQ patterns
Monitors consumer lag                   Fixes slow consumers
Scales brokers/partitions               Requests more partitions if needed
```

**An analogy:** You build the highway (Kafka cluster, topics, networking). They drive the cars (produce and consume messages). You don't drive the cars. They don't build the highway.

---

## The Transaction Flow (Verified Working)

```
Customer: "Send ₦75,000 to Adebayo"
    │
    ▼
[1] transaction-api (POST /api/v1/transactions)
    │ Creates transaction: status="pending", id="a1b99ea3..."
    │ Returns immediately to customer (200ms)
    │
    │──── In production: publishes event to Kafka ────────────────┐
    │     topic: "transactions.created"                           │
    ▼                                                             ▼
[2] fraud-detection (POST /api/v1/score)               [Kafka stores event]
    │ Scores: 0.1 (low risk)                                     │
    │ Flag: "round_amount" (75,000 is round)                     │
    │ Recommendation: "approve"                                   │
    │                                                             │
    ▼                                                             │
[3] payment-processor (POST /api/v1/process)  ◀──── consumes ────┘
    │ Simulates payment gateway call (427ms)
    │ Result: status="completed"
    │
    │──── publishes to: "transactions.processed" ──────────────┐
    │──── publishes to: "notifications.outbound" ──────────────┤
    ▼                                                           │
[4] account-service (GET /api/v1/accounts/acct-001/balance)    │
    │ Balance: ₦50,000                                          │
    │                                                           │
    ▼                                                           ▼
[5] notification-service (POST /api/v1/notify)  ◀── consumes ──┘
    │ Channel: SMS
    │ Status: "sent" (503ms delivery time)
    │
    ▼
📱 Customer receives: "Your payment of ₦75,000 was successful"
```

---

## Lab Steps

### Step 1: Verify All Services Are Healthy

```bash
kubectl get pods -n finflow --context kind-finflow
# All 5 should be 1/1 Running
```

### Step 2: Test HTTP Communication (Service-to-Service)

```bash
# Run a test pod that calls each service
kubectl run flow-test --rm -i --image=curlimages/curl:latest \
  -n finflow --context kind-finflow --restart=Never -- sh -c '
echo "1. transaction-api:" && curl -s http://transaction-api/health && echo ""
echo "2. payment-processor:" && curl -s http://payment-processor/health && echo ""
echo "3. account-service:" && curl -s http://account-service/health && echo ""
echo "4. fraud-detection:" && curl -s http://fraud-detection/health && echo ""
echo "5. notification-service:" && curl -s http://notification-service/health && echo ""
'
```

**What this proves:**
- Kubernetes DNS works (`transaction-api` resolves to the pod IP)
- Services are listening on the correct ports
- Health endpoints respond (application is running)

### Step 3: Simulate the Full Transaction Flow

```bash
kubectl run full-flow --rm -i --image=curlimages/curl:latest \
  -n finflow --context kind-finflow --restart=Never -- sh -c '

echo "=== STEP 1: Create Transaction ==="
curl -s -X POST http://transaction-api/api/v1/transactions \
  -H "Content-Type: application/json" \
  -d "{\"sender_account\":\"acct-001\",\"receiver_account\":\"acct-002\",\"amount\":25000,\"currency\":\"NGN\",\"type\":\"transfer\"}"
echo ""

echo "=== STEP 2: Score for Fraud ==="
curl -s -X POST http://fraud-detection/api/v1/score \
  -H "Content-Type: application/json" \
  -d "{\"transaction_id\":\"txn-test\",\"sender_account\":\"acct-001\",\"receiver_account\":\"acct-002\",\"amount\":25000,\"currency\":\"NGN\",\"type\":\"transfer\"}"
echo ""

echo "=== STEP 3: Process Payment ==="
curl -s -X POST http://payment-processor/api/v1/process \
  -H "Content-Type: application/json" \
  -d "{\"transaction_id\":\"txn-test\",\"sender_account\":\"acct-001\",\"receiver_account\":\"acct-002\",\"amount\":25000,\"currency\":\"NGN\",\"type\":\"transfer\"}"
echo ""

echo "=== STEP 4: Send Notification ==="
curl -s -X POST http://notification-service/api/v1/notify \
  -H "Content-Type: application/json" \
  -d "{\"recipient_id\":\"acct-001\",\"channel\":\"push\",\"type\":\"transaction_completed\",\"title\":\"Payment Sent\",\"message\":\"NGN 25000 sent to acct-002\"}"
echo ""
'
```

### Step 4: Test Cross-Namespace Kafka Connectivity

```bash
# Prove that pods in 'finflow' namespace can reach Kafka in 'finflow-kafka' namespace
kubectl run kafka-cross-ns --rm -i \
  --image=quay.io/strimzi/kafka:latest-kafka-4.2.0 \
  -n finflow --context kind-finflow --restart=Never -- sh -c '
echo "Producing from finflow namespace to Kafka..." &&
echo "{\"test\":\"cross-namespace works\",\"from\":\"finflow\"}" | \
  bin/kafka-console-producer.sh \
  --bootstrap-server finflow-kafka-kafka-bootstrap.finflow-kafka.svc.cluster.local:9092 \
  --topic transactions.created &&
echo "Consuming back..." &&
bin/kafka-console-consumer.sh \
  --bootstrap-server finflow-kafka-kafka-bootstrap.finflow-kafka.svc.cluster.local:9092 \
  --topic transactions.created --from-beginning --max-messages 1 --timeout-ms 10000
'
```

### Step 5: Simulate Event-Driven Flow via Kafka

```bash
# Terminal 1: Start a consumer (simulates payment-processor listening)
kubectl run payment-consumer --rm -i \
  --image=quay.io/strimzi/kafka:latest-kafka-4.2.0 \
  -n finflow-kafka --context kind-finflow --restart=Never -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server finflow-kafka-kafka-bootstrap:9092 \
  --topic transactions.created \
  --group payment-processor-group \
  --timeout-ms 60000

# Terminal 2: Produce messages (simulates transaction-api publishing)
for i in 1 2 3 4 5; do
  echo "{\"transaction_id\":\"txn-$i\",\"amount\":$((i * 10000)),\"status\":\"pending\"}"
done | kubectl run producer --rm -i \
  --image=quay.io/strimzi/kafka:latest-kafka-4.2.0 \
  -n finflow-kafka --context kind-finflow --restart=Never -- \
  bin/kafka-console-producer.sh \
  --bootstrap-server finflow-kafka-kafka-bootstrap:9092 \
  --topic transactions.created

# You should see the 5 messages appear in Terminal 1's consumer!
```

---

## Key Concepts Demonstrated

### Kubernetes DNS (Service Discovery)

```
From any pod in the cluster, you can reach any service by name:

Same namespace:     http://transaction-api/health
                    (short name works within same namespace)

Cross namespace:    http://finflow-kafka-kafka-bootstrap.finflow-kafka.svc.cluster.local:9092
                    └── service name ──────────────────┘ └── namespace ──┘ └── suffix ──────┘

Format: <service-name>.<namespace>.svc.cluster.local
```

### ConfigMap Provides Service Addresses

```yaml
# The ConfigMap (01-config.yaml) tells services where to find each other:
data:
  kafka-bootstrap-servers: "finflow-kafka-kafka-bootstrap.finflow-kafka.svc.cluster.local:9092"
  payment-processor-url: "http://payment-processor.finflow.svc.cluster.local"
  fraud-detection-url: "http://fraud-detection.finflow.svc.cluster.local"
```

In the application code, services read these values from environment variables (injected from ConfigMap). They never hardcode addresses.

### Why Services Don't Call Each Other's Pod IPs

```
❌ Wrong: curl http://10.244.1.5:8080/health
   → Pod IPs change on every restart!

✅ Right: curl http://transaction-api/health
   → Kubernetes Service provides a stable address
   → Automatically load-balances across all pods of that service
   → If a pod dies, traffic routes to healthy pods
```

---

## Lab Exercises

### Exercise 1: Test Fraud Detection with Different Amounts

```bash
# Low amount (should pass)
kubectl run test-low --rm -i --image=curlimages/curl:latest \
  -n finflow --context kind-finflow --restart=Never -- \
  curl -s -X POST http://fraud-detection/api/v1/score \
  -H "Content-Type: application/json" \
  -d '{"transaction_id":"t1","sender_account":"a1","receiver_account":"a2","amount":5000,"currency":"NGN","type":"transfer"}'

# High amount (should flag)
kubectl run test-high --rm -i --image=curlimages/curl:latest \
  -n finflow --context kind-finflow --restart=Never -- \
  curl -s -X POST http://fraud-detection/api/v1/score \
  -H "Content-Type: application/json" \
  -d '{"transaction_id":"t2","sender_account":"a1","receiver_account":"a2","amount":10000000,"currency":"NGN","type":"transfer"}'

# Self-transfer (suspicious)
kubectl run test-self --rm -i --image=curlimages/curl:latest \
  -n finflow --context kind-finflow --restart=Never -- \
  curl -s -X POST http://fraud-detection/api/v1/score \
  -H "Content-Type: application/json" \
  -d '{"transaction_id":"t3","sender_account":"a1","receiver_account":"a1","amount":5000000,"currency":"NGN","type":"transfer"}'
```

### Exercise 2: Test Account Transfer

```bash
kubectl run test-transfer --rm -i --image=curlimages/curl:latest \
  -n finflow --context kind-finflow --restart=Never -- sh -c '
echo "Before transfer:" &&
curl -s http://account-service/api/v1/accounts/acct-001/balance && echo "" &&
curl -s http://account-service/api/v1/accounts/acct-002/balance && echo "" &&
echo "Executing transfer..." &&
curl -s -X POST http://account-service/api/v1/transfers \
  -H "Content-Type: application/json" \
  -d "{\"from_account_id\":\"acct-001\",\"to_account_id\":\"acct-002\",\"amount\":10000,\"currency\":\"NGN\"}" && echo "" &&
echo "After transfer:" &&
curl -s http://account-service/api/v1/accounts/acct-001/balance && echo "" &&
curl -s http://account-service/api/v1/accounts/acct-002/balance
'
```

### Exercise 3: Kill a Service Mid-Flow

```bash
# Start a port-forward to transaction-api
kubectl port-forward svc/transaction-api 8080:80 -n finflow --context kind-finflow &

# Send a transaction
curl -s -X POST http://localhost:8080/api/v1/transactions \
  -H "Content-Type: application/json" \
  -d '{"sender_account":"acct-001","receiver_account":"acct-002","amount":5000,"currency":"NGN","type":"transfer"}'

# NOW kill fraud-detection
kubectl delete pod -l app=fraud-detection -n finflow --context kind-finflow

# Watch it come back (K8s self-healing)
kubectl get pods -n finflow -w --context kind-finflow

# Kill the port-forward
kill %1
```

**Discussion question:** In production with Kafka, if fraud-detection is down:
- The event sits in the topic waiting
- When fraud-detection restarts, it reads from its last offset
- No transaction is lost, just delayed
- This is WHY event-driven architecture is resilient

---

## Interview Questions You Can Now Answer

1. **"How do services discover each other in Kubernetes?"**
   → Kubernetes DNS. Each Service gets a DNS entry: `<name>.<namespace>.svc.cluster.local`. Pods use short names within the same namespace. No hardcoded IPs.

2. **"What's the difference between sync and async communication?"**
   → Sync (HTTP): Caller waits for response. Simple but creates coupling. If callee is down, caller fails.
   → Async (Kafka): Caller publishes event and continues. If consumer is down, events queue. No coupling between producer and consumer.

3. **"How do services get configuration (Kafka address, URLs)?"**
   → ConfigMaps injected as environment variables into pods. Platform team manages the ConfigMap. If an address changes, update ConfigMap + restart pods (or use config reloading).

4. **"What happens when a downstream service is unavailable?"**
   → With HTTP: Implement retries with backoff + circuit breaker (Istio handles this).
   → With Kafka: Events queue in the topic. Consumer processes them when it recovers. Zero data loss.

---

## What's Verified After This Lab

```
✅ All 5 services can reach each other via HTTP (Kubernetes DNS)
✅ Services in finflow namespace can reach Kafka in finflow-kafka namespace
✅ Full transaction flow works: create → score → process → notify
✅ Kafka produces/consumes work across namespaces
✅ ConfigMap has correct service addresses
✅ Platform is ready for backend developers to build on
```
