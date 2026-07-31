# How FinFlow Services Work Together

> Understanding the microservices architecture and how services communicate in a fintech system like Moniepoint.

---

## The Services

| Service | Language | Port | Responsibility |
|---------|----------|------|----------------|
| transaction-api | Go | 8080 | Entry point — receives payment requests from users |
| payment-processor | Go | 8081 | Validates and executes payments (debit/credit) |
| fraud-detection | Python | 8083 | Scores transactions for fraud risk |
| account-service | Go | 8082 | Manages account balances and transfers |
| notification-service | Python | 8084 | Sends SMS, email, and push notifications |

---

## The Flow: Customer Sends ₦50,000

```
Customer taps "Send Money" in mobile app
        │
        ▼
┌─────────────────────────────────────────────────────┐
│  STEP 1: Transaction API                             │
│                                                      │
│  POST /api/v1/transactions                           │
│  - Validates request (amount > 0, accounts valid)    │
│  - Creates transaction with status "pending"         │
│  - Publishes event to Kafka: "transactions.created"  │
│  - Returns transaction ID to customer immediately    │
└──────────────────────────┬──────────────────────────┘
                           │
                  Kafka Event Published
               topic: "transactions.created"
                           │
              ┌────────────┼────────────┐
              ▼                         ▼
┌──────────────────────┐   ┌──────────────────────────┐
│  STEP 2: Fraud        │   │  STEP 3: Payment         │
│  Detection            │   │  Processor               │
│                       │   │                          │
│  Scores transaction:  │   │  Waits for fraud score   │
│  - Amount normal?     │   │  Gets "approve" → calls  │
│  - Frequency ok?      │   │  Account Service:        │
│  - Suspicious?        │   │  - Deducts from sender   │
│                       │   │  - Credits receiver      │
│  Result: 0.12 (safe)  │   │  - Status → "completed" │
│  Recommendation:      │   │  - Publishes event:      │
│  "approve"            │   │    "notifications.       │
│                       │   │     outbound"            │
└──────────────────────┘   └────────────┬─────────────┘
                                        │
                                        ▼
                           ┌──────────────────────────┐
                           │  STEP 4: Notification     │
                           │  Service                  │
                           │                          │
                           │  Sends to sender:         │
                           │  📱 "Payment of ₦50,000  │
                           │     successful"           │
                           │                          │
                           │  Sends to receiver:       │
                           │  📱 "You received ₦50,000│
                           │     New balance: ₦175,000"│
                           └──────────────────────────┘
```

---

## Two Communication Patterns

### 1. Synchronous (HTTP) — "I need an answer NOW"

```
Payment Processor ──HTTP POST──→ Account Service
"Deduct ₦50,000 from acct-001"  → "Done" or "Insufficient balance"
```

Used when: The caller can't proceed without the response.

### 2. Asynchronous (Kafka) — "Something happened, react when ready"

```
Transaction API ──publishes──→ Kafka topic
                                    │
                                    ├──→ Fraud Detection (consumes)
                                    ├──→ Payment Processor (consumes)
                                    └──→ Audit/Analytics (consumes)
```

Used when: You don't want services waiting on each other. Fire-and-forget.

---

## Why Microservices (Not One Big App)?

| Problem | How Microservices Solve It |
|---------|--------------------------|
| Need to scale payments during peak | Scale payment-processor alone (other services stay the same) |
| Fraud detection ML model is slow | Circuit breaker isolates it. Payments still work. |
| Notification service crashes | Payments succeed. Notifications queue in Kafka, send on recovery. |
| Need to update fraud model | Deploy new version without touching other services. Canary test first. |
| Regulatory audit trail | Kafka keeps every event for 30 days. Full replay capability. |

---

## Where Cloud Engineering Comes In

The services are just code. YOUR job is building the platform that runs them:

```
What services need              What you provide
───────────────────             ──────────────────────────────────
"Run somewhere"                 → Kubernetes (GKE/EKS) with auto-scaling
"Talk securely"                 → Istio mTLS + authorization policies
"Store data"                    → MySQL (Cloud SQL) + ProxySQL for HA
"Publish events"                → Kafka cluster (Strimzi)
"Access secrets"                → Vault (dynamic credentials)
"Deploy safely"                 → ArgoCD + Jenkins (canary deployments)
"Know when broken"              → Prometheus + Grafana + Jaeger
"Survive datacenter failure"    → Multi-cloud (GCP + AWS) with failover
"Handle 10,000 req/s"          → HAProxy/Nginx + HPA auto-scaling
```
