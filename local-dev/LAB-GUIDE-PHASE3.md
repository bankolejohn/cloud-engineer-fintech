# Phase 3 Lab: Kafka Event Streaming

> After this lab you'll understand how event-driven architecture works and be able to answer: "How do your services communicate asynchronously?"

---

## What We're Building

```
┌─────────────────────────────────────────────────────────────────────────┐
│  finflow-kafka namespace                                                 │
│                                                                          │
│  ┌──────────────────────────┐    ┌────────────────────────────────────┐ │
│  │ Strimzi Operator          │    │ Kafka Broker (finflow-kafka)       │ │
│  │                           │    │                                     │ │
│  │ Watches for Kafka/Topic   │───▶│ Topics:                            │ │
│  │ CRDs and creates/manages  │    │  - transactions.created (3 parts) │ │
│  │ the actual Kafka cluster  │    │  - transactions.processed          │ │
│  │                           │    │  - transactions.fraud-scored        │ │
│  └──────────────────────────┘    │  - notifications.outbound           │ │
│                                   │  - finflow.dlq                      │ │
│                                   └─────────────┬──────────────────────┘ │
└─────────────────────────────────────────────────┼────────────────────────┘
                                                  │
                         ┌────────────────────────┼────────────────────────┐
                         │                        │                        │
                    PRODUCERS                 KAFKA BROKER              CONSUMERS
                  (write events)           (stores events)          (read events)
                         │                        │                        │
              transaction-api              Keeps messages             payment-processor
              "New payment created"       for 1 hour (local)        fraud-detection
                                          7 days (production)        notification-service
```

---

## Why Kafka (Recap)

| Without Kafka (synchronous) | With Kafka (asynchronous) |
|----------------------------|--------------------------|
| transaction-api calls payment-processor directly | transaction-api publishes event and returns immediately |
| If payment-processor is down → transaction fails | If payment-processor is down → events queue up, process on recovery |
| Adding a new consumer requires changing the producer | New consumer subscribes independently, no producer changes |
| One slow consumer blocks the whole chain | Each consumer processes at its own speed |

---

## Lab Steps

### Step 1: Install Strimzi Operator

```bash
# Add Strimzi Helm repo
helm repo add strimzi https://strimzi.io/charts/
helm repo update

# Install the operator (it manages Kafka clusters declaratively)
helm install strimzi strimzi/strimzi-kafka-operator \
  -n finflow-kafka \
  --kube-context kind-finflow

# Wait for operator to be ready
kubectl wait --for=condition=ready pod -l name=strimzi-cluster-operator \
  -n finflow-kafka --context kind-finflow --timeout=120s
```

**What the operator does:**
You write a `Kafka` YAML resource → Operator creates actual Kafka broker pods, configures networking, manages upgrades. Same pattern as Prometheus Operator manages Prometheus.

### Step 2: Deploy Kafka Cluster + Topics

```bash
kubectl apply -f local-dev/k8s/04-kafka.yaml --context kind-finflow
```

**What this creates:**

| Resource | What it is |
|----------|-----------|
| `KafkaNodePool/broker` | Defines broker pool (1 replica, ephemeral storage, resource limits) |
| `Kafka/finflow-kafka` | The cluster itself (version, listeners, config, entity operator) |
| `KafkaTopic/transactions.created` | Topic with 3 partitions for new transaction events |
| `KafkaTopic/transactions.processed` | Topic for payment processing results |
| `KafkaTopic/transactions.fraud-scored` | Topic for fraud risk scores |
| `KafkaTopic/notifications.outbound` | Topic that triggers notification delivery |
| `KafkaTopic/finflow.dlq` | Dead letter queue for failed messages |

**Wait for Kafka to be ready (~2 minutes):**
```bash
kubectl wait kafka/finflow-kafka --for=condition=Ready \
  -n finflow-kafka --context kind-finflow --timeout=300s
```

### Step 3: Verify Topics Exist

```bash
# List all topics using the Kafka CLI inside the cluster
kubectl run kafka-topics --rm -i \
  --image=quay.io/strimzi/kafka:latest-kafka-4.2.0 \
  -n finflow-kafka --context kind-finflow --restart=Never -- \
  bin/kafka-topics.sh --bootstrap-server finflow-kafka-kafka-bootstrap:9092 --list
```

Expected output:
```
finflow.dlq
notifications.outbound
transactions.created
transactions.fraud-scored
transactions.processed
```

### Step 4: Produce a Message (Simulate Transaction API)

```bash
# Produce a transaction event (what transaction-api would publish)
echo '{"transaction_id":"txn-100","sender_account":"acct-001","receiver_account":"acct-002","amount":50000,"currency":"NGN","type":"transfer","status":"pending","created_at":"2024-01-15T10:30:00Z"}' | \
kubectl run kafka-produce --rm -i \
  --image=quay.io/strimzi/kafka:latest-kafka-4.2.0 \
  -n finflow-kafka --context kind-finflow --restart=Never -- \
  bin/kafka-console-producer.sh \
  --bootstrap-server finflow-kafka-kafka-bootstrap:9092 \
  --topic transactions.created
```

**What just happened:**
- You simulated what the transaction-api would do after creating a transaction
- The message is now stored in the `transactions.created` topic
- It will stay there for 1 hour (retention period)
- Any consumer can read it independently

### Step 5: Consume the Message (Simulate Payment Processor)

```bash
# Consume from the beginning (what payment-processor would do)
kubectl run kafka-consume --rm -i \
  --image=quay.io/strimzi/kafka:latest-kafka-4.2.0 \
  -n finflow-kafka --context kind-finflow --restart=Never -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server finflow-kafka-kafka-bootstrap:9092 \
  --topic transactions.created \
  --from-beginning \
  --max-messages 1 \
  --timeout-ms 15000
```

You should see the JSON message you produced in Step 4.

### Step 6: Consumer Groups (The Key Concept)

```bash
# Start a consumer WITH a consumer group name
kubectl run consumer-group-test --rm -i \
  --image=quay.io/strimzi/kafka:latest-kafka-4.2.0 \
  -n finflow-kafka --context kind-finflow --restart=Never -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server finflow-kafka-kafka-bootstrap:9092 \
  --topic transactions.created \
  --from-beginning \
  --group payment-processor-group \
  --max-messages 1 \
  --timeout-ms 15000

# Check consumer group status
kubectl run kafka-groups --rm -i \
  --image=quay.io/strimzi/kafka:latest-kafka-4.2.0 \
  -n finflow-kafka --context kind-finflow --restart=Never -- \
  bin/kafka-consumer-groups.sh \
  --bootstrap-server finflow-kafka-kafka-bootstrap:9092 \
  --describe --group payment-processor-group
```

**What you'll see:**
```
GROUP                    TOPIC                PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG
payment-processor-group  transactions.created  0          1               1               0
payment-processor-group  transactions.created  1          0               0               0
payment-processor-group  transactions.created  2          0               0               0
```

- **CURRENT-OFFSET:** How far this consumer has read (1 message)
- **LOG-END-OFFSET:** How many messages exist in the partition (1)
- **LAG:** Messages not yet consumed (0 = fully caught up)

---

## Key Concepts Explained

### The Bootstrap Server

```
finflow-kafka-kafka-bootstrap:9092
└──────────┬───────────────────┘
           │
   Kubernetes Service that load-balances across all Kafka brokers.
   Every Kafka client connects here first to discover the cluster.
   
   Like a phone directory: "Call this number to find the actual broker."
```

### Partitions and Ordering

```
Topic: transactions.created (3 partitions)

Message with key="acct-001" → always goes to Partition 0
Message with key="acct-002" → always goes to Partition 1
Message with key="acct-003" → always goes to Partition 2

WHY: All transactions for the same account land in the same partition
     → Guaranteed ordering PER ACCOUNT
     → "Payment 1 is processed before Payment 2" for the same sender
```

### Consumer Group Magic

```
Scenario A: 1 consumer in group "payment-processor"
  Consumer-1 reads: P0, P1, P2 (all partitions alone)

Scenario B: 3 consumers in group "payment-processor"  
  Consumer-1 reads: P0
  Consumer-2 reads: P1
  Consumer-3 reads: P2
  → 3x throughput! Each consumer handles 1/3 of the load.

Scenario C: Consumer-2 crashes
  Kafka detects: "Consumer-2 is gone"
  Rebalances: Consumer-1 gets P0+P1, Consumer-3 gets P2
  → No messages lost. Other consumers pick up the work.
```

### Dead Letter Queue (DLQ)

```
Normal flow:
  Consumer reads message → processes successfully → commits offset → next message

Error flow:
  Consumer reads message → processing FAILS (bad data, timeout, etc.)
  → Retry 3 times
  → Still failing? → Publish to finflow.dlq topic
  → Commit offset (move on, don't block other messages)
  → Engineer investigates DLQ messages later

WHY: One bad message shouldn't block thousands of good ones behind it.
```

---

## Lab Exercises

### Exercise 1: Produce Multiple Messages

```bash
# Produce 10 transactions
for i in $(seq 1 10); do
  echo "{\"transaction_id\":\"txn-$i\",\"amount\":$((RANDOM % 100000)),\"currency\":\"NGN\"}"
done | kubectl run kafka-bulk --rm -i \
  --image=quay.io/strimzi/kafka:latest-kafka-4.2.0 \
  -n finflow-kafka --context kind-finflow --restart=Never -- \
  bin/kafka-console-producer.sh \
  --bootstrap-server finflow-kafka-kafka-bootstrap:9092 \
  --topic transactions.created
```

### Exercise 2: See Partition Distribution

```bash
# Check how messages are distributed across partitions
kubectl run kafka-offsets --rm -i \
  --image=quay.io/strimzi/kafka:latest-kafka-4.2.0 \
  -n finflow-kafka --context kind-finflow --restart=Never -- \
  bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
  --broker-list finflow-kafka-kafka-bootstrap:9092 \
  --topic transactions.created
```

### Exercise 3: Multiple Consumer Groups (Independence)

```bash
# Consumer group A reads the messages
kubectl run group-a --rm -i --image=quay.io/strimzi/kafka:latest-kafka-4.2.0 \
  -n finflow-kafka --context kind-finflow --restart=Never -- \
  bin/kafka-console-consumer.sh --bootstrap-server finflow-kafka-kafka-bootstrap:9092 \
  --topic transactions.created --from-beginning --group fraud-detection --max-messages 5 --timeout-ms 15000

# Consumer group B reads the SAME messages independently
kubectl run group-b --rm -i --image=quay.io/strimzi/kafka:latest-kafka-4.2.0 \
  -n finflow-kafka --context kind-finflow --restart=Never -- \
  bin/kafka-console-consumer.sh --bootstrap-server finflow-kafka-kafka-bootstrap:9092 \
  --topic transactions.created --from-beginning --group notification-service --max-messages 5 --timeout-ms 15000

# Both groups read ALL messages — they don't interfere with each other
```

---

## Interview Questions You Can Now Answer

1. **"Why Kafka over a simple REST call between services?"**
   → Decoupling (producer doesn't know/care about consumers), resilience (messages persist if consumer is down), scalability (add more consumers for throughput), replay (new services can read historical events).

2. **"How do you scale Kafka consumers?"**
   → Add more consumers to the consumer group (up to partition count). Kafka automatically rebalances partitions across group members.

3. **"What happens if a Kafka consumer crashes?"**
   → Kafka detects missing heartbeat, triggers rebalance, reassigns partitions to surviving consumers. Messages are NOT lost — processing resumes from last committed offset.

4. **"How do you handle messages that can't be processed?"**
   → Retry N times, then publish to DLQ (dead letter queue). Don't block the partition. Investigate DLQ messages separately.

5. **"How do you manage Kafka in Kubernetes?"**
   → Strimzi operator. Declare Kafka clusters, topics, and users as CRDs. Operator handles deployment, scaling, upgrades, configuration.

---

## What's Running After This Lab

```
finflow-kafka namespace:
  ✅ Strimzi Cluster Operator
  ✅ Kafka Broker (finflow-kafka-broker-0)
  ✅ Entity Operator (manages topics/users)
  ✅ 5 Topics created and verified

Bootstrap server (for service configs):
  finflow-kafka-kafka-bootstrap.finflow-kafka.svc.cluster.local:9092
```

---

## Access Quick Reference

```bash
# List topics
kubectl run kt --rm -i --image=quay.io/strimzi/kafka:latest-kafka-4.2.0 \
  -n finflow-kafka --context kind-finflow --restart=Never -- \
  bin/kafka-topics.sh --bootstrap-server finflow-kafka-kafka-bootstrap:9092 --list

# Produce a message
echo '{"msg":"hello"}' | kubectl run kp --rm -i \
  --image=quay.io/strimzi/kafka:latest-kafka-4.2.0 \
  -n finflow-kafka --context kind-finflow --restart=Never -- \
  bin/kafka-console-producer.sh --bootstrap-server finflow-kafka-kafka-bootstrap:9092 --topic transactions.created

# Consume messages
kubectl run kc --rm -i --image=quay.io/strimzi/kafka:latest-kafka-4.2.0 \
  -n finflow-kafka --context kind-finflow --restart=Never -- \
  bin/kafka-console-consumer.sh --bootstrap-server finflow-kafka-kafka-bootstrap:9092 \
  --topic transactions.created --from-beginning --max-messages 5 --timeout-ms 15000

# Check consumer group lag
kubectl run kg --rm -i --image=quay.io/strimzi/kafka:latest-kafka-4.2.0 \
  -n finflow-kafka --context kind-finflow --restart=Never -- \
  bin/kafka-consumer-groups.sh --bootstrap-server finflow-kafka-kafka-bootstrap:9092 \
  --describe --group payment-processor-group
```
