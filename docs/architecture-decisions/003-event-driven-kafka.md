# ADR-003: Kafka for Event-Driven Architecture

## Status
Accepted

## Context
Transaction processing requires:
- Asynchronous processing for high throughput
- Event sourcing for audit trails (financial compliance)
- Decoupling between services for independent scaling
- Guaranteed message delivery for payment events

## Decision
Use Apache Kafka (via Strimzi operator on Kubernetes) as the event backbone because:
- High throughput (millions of messages/sec) suitable for transaction volumes
- Strong durability guarantees with replication
- Built-in partitioning for parallel processing
- Kafka Connect for CDC (Debezium) and data integration
- Mature ecosystem for financial services

## Consequences
- Operational complexity of managing Kafka clusters (mitigated by Strimzi operator)
- Need for schema management (addressed with Schema Registry)
- Consumer lag monitoring required (Prometheus + Grafana dashboards)
- Gain: Reliable event delivery, audit trail, service decoupling, replay capability
