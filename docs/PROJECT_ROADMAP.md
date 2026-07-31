# FinFlow Project Roadmap

> A phased plan for building, deploying, and learning from this project.
> We do EVERYTHING locally first (free), then move to the cloud (paid).

---

## The Two Stages

```
┌──────────────────────────────────────────────────────────────────────────┐
│  STAGE 1: LOCAL (Free — Kind cluster on your laptop)                      │
│                                                                           │
│  Goal: Learn every tool, break things safely, build confidence            │
│  Duration: 4-6 weeks                                                      │
│  Cost: $0                                                                 │
│  Branch: local-dev                                                        │
│                                                                           │
│  Phases 1 → 7                                                             │
└──────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  STAGE 2: CLOUD (Paid — GCP + AWS with free credits)                      │
│                                                                           │
│  Goal: Deploy for real, practice multi-cloud, build portfolio             │
│  Duration: 3-4 weeks                                                      │
│  Cost: Free credits ($300 GCP + AWS free tier)                            │
│  Branch: main                                                             │
│                                                                           │
│  Phases 8 → 11                                                            │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## STAGE 1: LOCAL DEVELOPMENT (Phases 1-7)

---

### Phase 1: Foundation ✅ DONE

**What we did:**
- Created Kind cluster (1 control plane + 2 workers with zone labels)
- Built 5 Docker images (multi-stage, distroless)
- Deployed all services to Kubernetes
- Verified health checks and API responses

**What you learned:**
- Docker multi-stage builds
- Kubernetes Deployments, Services, ConfigMaps, Secrets
- Pod scheduling across nodes
- Port-forwarding for local access
- kubectl basics (get, describe, logs, exec)

**Status:** Complete. Services running on `kind-finflow` cluster.

---

### Phase 2: Observability (Prometheus + Grafana)

**What we'll build:**
- Deploy Prometheus (collects metrics from all services)
- Deploy Grafana (visualizes metrics in dashboards)
- Import the FinFlow dashboard (transaction rate, error rate, latency)
- Create alerting rules (high error rate, pod crash)

**Why this comes second:**
You need to SEE what's happening before you add complexity. When we add Kafka and Istio later, you'll be able to watch the impact in real-time on Grafana dashboards.

**What you'll learn:**
- Prometheus metrics collection (scraping, PromQL)
- Grafana dashboard design
- AlertManager configuration
- How /metrics endpoint works
- The RED method (Rate, Errors, Duration)

**Lab exercises:**
- Generate traffic with a load script
- Watch latency graphs change in real-time
- Trigger an alert by killing pods
- Write a custom PromQL query

---

### Phase 3: Kafka (Event Streaming)

**What we'll build:**
- Deploy Kafka (using Strimzi operator on Kind)
- Create topics (transactions.created, transactions.processed, etc.)
- Wire services to produce/consume events
- Deploy a Kafka UI (for visual topic inspection)
- Set up consumer groups with lag monitoring

**Why this is Phase 3:**
Kafka is the backbone of how services communicate asynchronously. Once Kafka is running, you can see the full transaction flow: API → Kafka → Processor → Kafka → Notification.

**What you'll learn:**
- Kafka cluster management (Strimzi operator)
- Topic creation with partition/replication strategies
- Producer/Consumer patterns
- Consumer groups and rebalancing
- Monitoring consumer lag in Grafana
- Dead letter queues for failed messages

**Lab exercises:**
- Produce a message to a topic manually (kafka-console-producer)
- Watch it appear in the consumer
- Scale up consumers, watch partitions rebalance
- Stop a consumer, watch lag grow, restart and catch up
- Break a broker, see replication keep data safe

---

### Phase 4: Service-to-Service Communication

**What we'll build:**
- Update services to actually call each other (HTTP)
- transaction-api → fraud-detection → payment-processor → notification-service
- Add Kafka event production to transaction-api
- Add Kafka consumption to payment-processor and notification-service
- Test the full end-to-end flow

**Why this is Phase 4:**
Now that Kafka and monitoring exist, we can wire the services together and WATCH the entire transaction flow on the dashboard. This is where it starts feeling like a real system.

**What you'll learn:**
- Service discovery via Kubernetes DNS
- HTTP inter-service calls with retries
- Event-driven architecture in practice
- Error handling (what happens when fraud-detection is slow?)
- Distributed tracing concepts

**Lab exercises:**
- Create a transaction and trace it through all 5 services
- Make fraud-detection return "block" and see payment fail
- Stop notification-service, see events queue in Kafka
- Restart notification-service, see backlog process

---

### Phase 5: Istio Service Mesh

**What we'll build:**
- Install Istio on the Kind cluster
- Enable sidecar injection for finflow namespace
- Configure mTLS (automatic encryption)
- Set up VirtualServices for canary routing
- Configure circuit breakers
- Test fault injection (chaos engineering)

**Why this is Phase 5:**
Istio adds a LOT of complexity. You need to understand the basics (K8s, services talking to each other, monitoring) before adding the mesh layer. But once it's in, you get mTLS, traffic management, and observability "for free."

**What you'll learn:**
- Istio architecture (control plane vs data plane)
- Envoy sidecar injection
- Mutual TLS without code changes
- Traffic splitting (canary deployments)
- Circuit breaking and retry policies
- Fault injection for resilience testing
- Kiali service graph visualization

**Lab exercises:**
- Deploy v2 of transaction-api alongside v1
- Route 10% of traffic to v2, watch metrics
- Inject a 5-second delay into payment-processor
- Watch circuit breaker trip in Grafana
- Configure authorization policies (who can call whom)

---

### Phase 6: ArgoCD (GitOps)

**What we'll build:**
- Install ArgoCD on the Kind cluster
- Create Application definitions for all services
- Set up App of Apps pattern
- Practice deploying via git commit (not kubectl apply)
- Test self-healing (manual change gets reverted)
- Implement canary rollout with Argo Rollouts

**Why this is Phase 6:**
GitOps is the deployment model. Once ArgoCD is in, you stop using `kubectl apply` and start deploying by pushing to Git. This is how real companies deploy.

**What you'll learn:**
- GitOps principles (Git = source of truth)
- ArgoCD Application definitions
- Sync policies (automatic vs manual)
- Rollback via git revert
- Self-healing (cluster always matches Git)
- Progressive delivery with Argo Rollouts

**Lab exercises:**
- Change an image tag in Git, watch ArgoCD deploy it
- Manually scale a deployment with kubectl, watch ArgoCD revert it
- Configure a canary rollout (10% → 50% → 100%)
- Simulate a bad deploy, watch automatic rollback

---

### Phase 7: Security (Vault + Network Policies)

**What we'll build:**
- Deploy Vault (dev mode for local — single node, in-memory)
- Configure Kubernetes authentication
- Set up dynamic database secrets
- Replace hardcoded credentials with Vault injection
- Apply Network Policies (default deny + allow rules)
- Verify inter-service communication restrictions

**Why this is last locally:**
Security is the final layer. It restricts and locks things down. You need everything working first, then you secure it. In production you'd plan security from day 1, but for learning it's easier to add incrementally.

**What you'll learn:**
- Vault in dev mode vs production mode
- Kubernetes auth method
- Dynamic secrets lifecycle (create → use → expire → rotate)
- Vault Agent sidecar injection
- Network Policies (default deny, explicit allow)
- Zero-trust networking concepts

**Lab exercises:**
- Get dynamic DB credentials from Vault, watch them expire
- Block all traffic with default-deny, see services break
- Add allow rules one by one, see services recover
- Try to call payment-processor from notification-service (should be blocked)

---

## STAGE 2: CLOUD DEPLOYMENT (Phases 8-11)

> Start this after completing Phases 1-7 locally.
> Use GCP $300 free credits + AWS free tier.
> Destroy resources daily to conserve credits.

---

### Phase 8: Single Cloud (GCP)

**What we'll build:**
- Terraform the GCP VPC + GKE cluster (from our modules)
- Push Docker images to Google Artifact Registry
- Deploy services to real GKE
- Set up Cloud SQL (MySQL) with private networking
- Configure Vault with GCP KMS auto-unseal
- Set up real Prometheus + Grafana (via Helm)

**What you'll learn:**
- Terraform init/plan/apply cycle for real
- GCP Console navigation
- Remote state management (GCS bucket)
- Real private networking (Cloud NAT, private GKE)
- Cloud SQL with automated backups
- IAM and service accounts

**Cost management:**
- Use `e2-small` nodes (cheapest)
- 1 node cluster (scale to 0 when not working)
- `terraform destroy` at end of each day
- Preemptible/Spot nodes for 60-80% discount

---

### Phase 9: Multi-Cloud (Add AWS)

**What we'll build:**
- Terraform the AWS VPC + EKS cluster
- Set up cross-cloud VPN (GCP ↔ AWS)
- Deploy same services to EKS
- Configure Istio multi-cluster mesh
- Test failover (stop GCP pods, traffic routes to AWS)

**What you'll learn:**
- AWS EKS vs GCP GKE differences
- Cross-cloud networking (VPN, BGP)
- Multi-cluster Istio (East-West gateways)
- Locality-aware load balancing
- Disaster recovery failover

**Cost management:**
- AWS free tier EKS (control plane is free)
- t3.small nodes (cheapest with enough resources)
- VPN is ~$0.05/hour when running
- Destroy daily

---

### Phase 10: CI/CD for Real

**What we'll build:**
- Set up a real Jenkins instance (or use GitHub Actions as alternative)
- Configure pipeline: build → scan → push → deploy
- Set up ArgoCD on GKE watching your GitHub repo
- Deploy via pull request merge
- Configure Slack notifications

**What you'll learn:**
- Real CI/CD end-to-end
- Container registry (Artifact Registry / ECR)
- Image scanning in pipeline (Trivy)
- GitOps with real clusters
- PR-based deployments

---

### Phase 11: Polish & Portfolio

**What we'll build:**
- Architecture diagram (draw.io or Mermaid)
- Screen recordings of key demos (canary deploy, failover, chaos test)
- Blog post: "How I Built a Multi-Cloud Fintech Platform"
- Clean up repo README with screenshots
- Record a 5-minute architecture walkthrough video

**What you'll learn:**
- How to present technical work
- Architecture documentation
- Storytelling for interviews

---

## Progress Tracker

| Phase | Topic | Status | Branch |
|-------|-------|--------|--------|
| 1 | Foundation (Kind + Services) | ✅ Done | local-dev |
| 2 | Observability (Prometheus + Grafana) | ⬜ Next | local-dev |
| 3 | Kafka (Event Streaming) | ⬜ | local-dev |
| 4 | Service Communication (wire it up) | ⬜ | local-dev |
| 5 | Istio (Service Mesh) | ⬜ | local-dev |
| 6 | ArgoCD (GitOps) | ⬜ | local-dev |
| 7 | Security (Vault + Network Policies) | ⬜ | local-dev |
| 8 | Single Cloud (GCP) | ⬜ | main |
| 9 | Multi-Cloud (GCP + AWS) | ⬜ | main |
| 10 | CI/CD for Real | ⬜ | main |
| 11 | Polish & Portfolio | ⬜ | main |

---

## Time Estimate

| Stage | Phases | Duration | Cost |
|-------|--------|----------|------|
| Local | 1-7 | 4-6 weeks (2-3 hrs/day) | Free |
| Cloud | 8-11 | 3-4 weeks (2-3 hrs/day) | Free (credits) |
| **Total** | **1-11** | **7-10 weeks** | **$0** |

---

## Rules for Maximum Learning

1. **Don't skip phases.** Each one builds on the previous.
2. **Break things intentionally.** Fixing is where real learning happens.
3. **Explain out loud.** If you can't explain it simply, you don't understand it yet.
4. **Take notes.** Write what confused you and how you resolved it.
5. **Destroy and recreate.** Don't just `kubectl apply` once. Delete everything and redo it from scratch until it's muscle memory.
6. **Connect it to the interview.** After each phase, ask: "What interview question can I now answer?"
