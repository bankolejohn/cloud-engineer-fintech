# Kafka Operations — Who Does What (Real Company Breakdown)

> Understanding the responsibilities around Kafka at a fintech company like Moniepoint.

---

## The Three Roles

| Role | Kafka Responsibility |
|------|---------------------|
| **Cloud/Platform Engineer** (you) | Deploys and manages the Kafka CLUSTER. Creates topics and users via GitOps. Monitors health, lag, disk. |
| **Backend/Software Engineer** | Writes application code that produces/consumes events. Defines event schemas. |
| **Tech Lead / Architect** | Designs event-driven architecture. Decides topic ownership and data contracts between teams. |

---

## The Workflow: Developer Needs a New Topic

### Step 1: Developer Submits a PR

```
Developer (Tunde):
  "I'm building the disbursement service. I need a topic called 
   'disbursements.initiated' with 6 partitions."

What he submits (PR to your infrastructure repo):
  - A KafkaTopic YAML file
  - A KafkaUser YAML file (what permissions his service needs)
  - Justification in PR description (expected throughput, retention needs)
```

### Step 2: Platform Engineer (You) Reviews

```
Your review checklist:
  □ Naming convention followed? (domain.event-name format)
  □ Partition count justified? (matches expected throughput)
  □ Retention appropriate? (7 days? 30 days for compliance?)
  □ Replication factor = 3? (production requirement)
  □ KafkaUser has LEAST PRIVILEGE?
    - Producer can ONLY write to their specific topic
    - Consumer can ONLY read what they need
    - No wildcard access
```

### Step 3: GitOps Deploys

```
PR merged → ArgoCD detects → kubectl apply → topic + user created

Audit trail: "Tunde requested, you approved, ArgoCD deployed at 14:32 UTC"
No one SSHed into anything. No CLI commands run manually.
```

---

## Who Creates What

| Resource | Who Creates | How | When |
|----------|-------------|-----|------|
| Kafka Cluster | Platform Engineer | Terraform + Strimzi Helm | Once (then maintain) |
| KafkaTopic | Platform Engineer reviews, Backend Dev submits PR | CRD in Git → ArgoCD | When service needs a new event channel |
| KafkaUser | Platform Engineer | CRD in Git → ArgoCD | When service is deployed or needs Kafka access |
| Producer/Consumer code | Backend Developer | Application code | During feature development |
| Topic deletion | Platform Engineer (with data owner approval) | PR + review | Rarely (dangerous) |

---

## Access Control (KafkaUser ACLs)

Each service gets its own Kafka identity with minimum permissions:

```yaml
# transaction-api: Can ONLY produce to transactions.created
acls:
  - resource: {type: topic, name: transactions.created}
    operations: [Write, Describe]

# fraud-detection: Can ONLY read transactions.created and write fraud scores
acls:
  - resource: {type: topic, name: transactions.created}
    operations: [Read, Describe]
  - resource: {type: topic, name: transactions.fraud-scored}
    operations: [Write, Describe]

# notification-service: Can ONLY read notifications.outbound
acls:
  - resource: {type: topic, name: notifications.outbound}
    operations: [Read, Describe]
```

**If a developer asks for "all topics" access → DENY.**
"You only get access to what your service needs. Nothing more."

---

## Platform Engineer's Ongoing Responsibilities

| Task | How Often | What You Watch |
|------|-----------|----------------|
| Cluster health | Always (Prometheus alerts) | Broker up/down, disk usage, CPU |
| Consumer lag | Always (Grafana dashboard) | Lag > 10,000 messages → alert |
| Topic growth | Weekly | Any topic growing faster than expected? |
| Broker scaling | Monthly / as needed | Do we need more brokers for throughput? |
| Version upgrades | Quarterly | Strimzi/Kafka version patches |
| ACL audit | Monthly | Any over-permissioned users? |
| Retention review | Quarterly | Are we keeping data longer than needed? |

---

## Local vs Production

| Aspect | What we did locally | What happens in production |
|--------|-------------------|---------------------------|
| Cluster setup | `helm install strimzi` + KafkaNodePool CRD | Same, but with HA, persistent storage, monitoring |
| Topic creation | `kubectl apply -f 04-kafka.yaml` | ArgoCD syncs from Git (no manual kubectl) |
| Authentication | None (plain, no auth) | TLS + KafkaUser with strict ACLs |
| Brokers | 1 broker, ephemeral | 3+ brokers, 100Gi SSD, cross-zone |
| Partitions | 3 per topic | 12 per topic (more parallelism) |
| Retention | 1 hour | 7-30 days (compliance/audit) |
| Monitoring | Prometheus scrapes broker | Prometheus + Grafana dashboard + consumer lag alerts |

---

## Interview Answer Template

> "Who manages Kafka topics and access at your company?"

"The platform engineering team owns Kafka infrastructure. Topics and users are defined as Strimzi CRDs stored in Git. Backend teams submit PRs to request new topics — we review for naming conventions, partition count, retention policy, and least-privilege access. ArgoCD deploys changes on merge. No one has direct CLI access to production brokers. Every change is auditable via git history."
