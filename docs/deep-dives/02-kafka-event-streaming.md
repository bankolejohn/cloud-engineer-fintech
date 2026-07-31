# Apache Kafka — Event Streaming Deep Dive

> How Kafka works, why it's not just "AWS SNS/SQS", and how FinFlow uses it for transaction processing.

---

## What Kafka Is (One Line)

An append-only commit log that records events in order, keeps them for days/weeks, and lets multiple consumers read at their own pace.

---

## Kafka vs AWS Services

| Feature | SNS | SQS | Kafka |
|---------|-----|-----|-------|
| Message kept after reading? | No | No | **Yes** (for days/weeks) |
| Multiple consumers read same message? | Yes (fan-out) | No | **Yes** (consumer groups) |
| Ordering guaranteed? | No | FIFO only | **Yes** (per partition) |
| Replay old messages? | No | No | **Yes** (reset offset) |
| Throughput | Medium | Medium | **Millions/sec** |
| Best analogy | Live radio broadcast | Voicemail box | **CCTV recording** |

---

## Core Concepts

### Topic
A named channel for messages. Like a YouTube channel — producers post, consumers subscribe.

```
Topic: "transactions.created"
│ msg-1 │ msg-2 │ msg-3 │ msg-4 │ msg-5 │ msg-6 │ ...
Messages are APPENDED. Never modified. Never deleted (until retention expires).
```

### Partition
A topic is split into partitions for parallel processing.

```
Topic: "transactions.created" (12 partitions)

Partition 0:  │ msg-A │ msg-D │ msg-G │ ...
Partition 1:  │ msg-B │ msg-E │ msg-H │ ...
Partition 2:  │ msg-C │ msg-F │ msg-I │ ...

More partitions = more consumers can work simultaneously.
Key insight: Same account's transactions go to same partition (ordering guarantee).
```

### Consumer Group
A team of consumers sharing the work. Each partition read by exactly one member.

```
3 consumers in group "payment-processor":
  consumer-1 → reads partitions 0,1,2,3
  consumer-2 → reads partitions 4,5,6,7
  consumer-3 → reads partitions 8,9,10,11

Scale to 6 consumers → each handles 2 partitions.
Scale to 12 → each handles 1 partition (maximum parallelism).
Scale to 15 → 3 sit idle (can't have more consumers than partitions).
```

### Offset
A bookmark. "I've read up to message #1523." If consumer crashes, resumes from its offset.

### Retention
How long messages are kept. `retention.ms: 604800000` = 7 days.
Messages exist whether they're read or not. New services can read historical data.

---

## Why Moniepoint Needs Kafka (Not SQS)

1. **Audit trail:** Every event stored for 30 days. Regulators can audit transaction history.
2. **Resilience:** If fraud-detection is down for 2 hours, messages queue up and process on recovery. Nothing lost.
3. **Multiple consumers:** Same transaction event consumed by fraud-detection AND payment-processor AND analytics — independently.
4. **Replay:** Deploy a new service today, read events from 7 days ago to backfill.

---

## Kafka Connect & Debezium CDC

### The Problem
How do you publish events for EVERY database change (even direct DBA fixes)?

### The Solution: Change Data Capture
Debezium watches MySQL's binary log and automatically publishes every INSERT/UPDATE/DELETE as a Kafka event.

```
App writes to MySQL → MySQL records in binlog → Debezium reads binlog → Publishes to Kafka

Benefits:
- App code only writes to DB (simple)
- Every change captured (no missed events)
- Works for any source of writes (app, DBA, migration scripts)
```

### CDC Event Format
```json
{
  "op": "c",              // "c"=create, "u"=update, "d"=delete
  "before": null,         // Previous state
  "after": {             // New state
    "id": "txn-123",
    "amount": 50000,
    "status": "completed"
  }
}
```

---

## Consumer Group Rebalancing

When a consumer crashes or scales:

```
Before crash: 3 consumers handling 12 partitions (4 each)
Consumer-2 crashes!
→ Kafka detects missing heartbeat
→ Redistributes consumer-2's partitions to survivors
→ No messages lost (resumes from committed offset)
→ Kubernetes HPA starts replacement pod
→ Rebalances again (back to even distribution)
```

---

## FinFlow Topic Design

| Topic | Partitions | Retention | Purpose |
|-------|-----------|-----------|---------|
| transactions.created | 12 | 7 days | Every new transaction |
| transactions.processed | 12 | 7 days | Processing results |
| transactions.status | 12 | Forever (compacted) | Latest status per transaction |
| transactions.fraud-scored | 6 | 30 days | Fraud scores (audit) |
| notifications.outbound | 6 | 3 days | Notifications to send |
| finflow.dlq | 3 | 30 days | Failed messages for investigation |
| cdc.finflow.transactions | 6 | 7 days | Database CDC events |

---

## Key Files in This Repo

```
kafka/cluster.yaml       → Strimzi Kafka cluster (3 brokers, 3 ZK)
kafka/topics.yaml        → All topic definitions with partition/retention config
kafka/connect.yaml       → Debezium CDC + S3 Sink connectors
kafka/users.yaml         → Per-service ACLs (least privilege)
kafka/metrics-config.yaml → JMX metrics for Prometheus monitoring
```
