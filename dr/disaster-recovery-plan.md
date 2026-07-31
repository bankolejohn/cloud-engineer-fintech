# FinFlow Disaster Recovery Plan

## Overview

| Metric | Target |
|--------|--------|
| **RPO** (Recovery Point Objective) | 5 minutes |
| **RTO** (Recovery Time Objective) | 15 minutes |
| **Availability Target** | 99.99% |

## Architecture for DR

```
Primary (GCP us-central1)          Secondary (AWS us-east-1)
┌─────────────────────────┐        ┌─────────────────────────┐
│  GKE Cluster (Active)    │        │  EKS Cluster (Standby)   │
│  Cloud SQL (Primary)     │───────▶│  RDS (Read Replica)      │
│  Kafka (Active)          │        │  Kafka (Mirror)          │
│  Vault (Primary)         │        │  Vault (DR Replica)      │
└─────────────────────────┘        └─────────────────────────┘
            │                                  │
            └──────── VPN Tunnel ──────────────┘
```

## Failure Scenarios

### Scenario 1: Single Pod/Service Failure
- **Detection:** Kubernetes liveness probe (10s)
- **Recovery:** Automatic pod restart + HPA scaling
- **Impact:** Zero (other pods serve traffic)

### Scenario 2: Single Zone Failure
- **Detection:** Node health checks (30s)
- **Recovery:** Pods rescheduled to healthy zones via topology spread
- **Impact:** Brief latency increase during rescheduling

### Scenario 3: Primary Database Failure
- **Detection:** ProxySQL health check (5s) + Cloud SQL monitoring
- **Recovery:** Automatic failover to Cloud SQL HA replica
- **Impact:** 30-60s write unavailability

### Scenario 4: Primary Cloud Region Failure
- **Detection:** Istio health checks + external monitoring
- **Recovery:** DNS failover to AWS secondary cluster
- **RTO:** 5-15 minutes
- **Steps:**
  1. Istio locality failover routes traffic to AWS
  2. Promote RDS read replica to primary
  3. Kafka MirrorMaker activates for event continuity
  4. Vault DR replication promotes secondary

### Scenario 5: Complete Cloud Provider Failure
- **Detection:** External synthetic monitoring
- **Recovery:** Full failover to secondary provider
- **RTO:** 15-30 minutes

## Failover Procedures

### Automated Failover (Scenarios 1-3)
No human intervention needed. Kubernetes, Istio, and ProxySQL handle automatically.

### Manual Failover (Scenarios 4-5)

```bash
# Execute failover script
./scripts/failover.sh --target aws --confirm

# Steps performed:
# 1. Update DNS records (Route53/Cloud DNS)
# 2. Promote database replica
# 3. Scale up AWS EKS workloads
# 4. Verify service health
# 5. Notify team via Slack/PagerDuty
```

## Testing Schedule

| Test Type | Frequency | Last Tested |
|-----------|-----------|-------------|
| Pod kill (chaos) | Weekly | Automated |
| Zone failure simulation | Monthly | - |
| Database failover | Monthly | - |
| Full region failover | Quarterly | - |
| Complete DR drill | Semi-annually | - |

## Backup Strategy

| Component | Method | Frequency | Retention |
|-----------|--------|-----------|-----------|
| MySQL | Cloud SQL automated backup + PITR | Continuous | 30 days |
| Kafka | Topic replication (RF=3) + MirrorMaker | Real-time | 7 days |
| Vault | Raft snapshots | Hourly | 30 days |
| Kubernetes | Velero backups | Daily | 14 days |
| Terraform state | GCS versioning | Every apply | 90 days |
