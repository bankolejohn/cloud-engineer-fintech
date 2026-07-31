# FinFlow Learning Roadmap

> A structured guide for junior DevOps engineers working toward senior-level cloud engineering.
> Estimated timeline: 12-16 weeks (2-3 hours/day)

---

## How to Use This Guide

1. **Follow the phases in order** — each one builds on the previous
2. **Don't just read the code** — deploy it, break it, fix it
3. **Document what you learn** — write notes in your own words
4. **Use free tiers** — GCP ($300 credit), AWS (free tier), Azure ($200), OCI (always-free)
5. **One cloud at a time** — Start with GCP, then add AWS. Don't try all 4 simultaneously.

### The Learning Pattern for Each Topic

```
1. WHAT — What is this tool? What problem does it solve?
2. WHY — Why did we choose this over alternatives?
3. HOW — How does it work? Read the config, then deploy it.
4. BREAK — Intentionally break it. See what happens.
5. FIX — Fix it. This is where real learning happens.
6. EXPLAIN — Can you explain it to someone? If not, go back to step 1.
```

---

## Phase 1: Foundations (Weeks 1-2)

### Goal: Understand containers, Kubernetes basics, and the application layer

Before touching infrastructure, you need to understand what we're deploying.

### Week 1: Docker & The Application

**What to learn:**
- How multi-stage Docker builds work
- Why we use distroless/slim base images (security + size)
- What each microservice does in the FinFlow system

**Files to study:**
```
docker/transaction-api.Dockerfile
services/transaction-api/main.go
services/fraud-detection/app.py
```

**Exercises:**
1. Build the transaction-api Docker image locally:
   ```bash
   cd services/transaction-api
   docker build -f ../../docker/transaction-api.Dockerfile -t finflow/transaction-api:dev ../..
   ```
2. Run it: `docker run -p 8080:8080 finflow/transaction-api:dev`
3. Hit the API: `curl localhost:8080/health`
4. Create a transaction: 
   ```bash
   curl -X POST localhost:8080/api/v1/transactions \
     -H "Content-Type: application/json" \
     -d '{"sender_account":"acct-001","receiver_account":"acct-002","amount":5000,"currency":"NGN","type":"transfer"}'
   ```

**Key concepts to research:**
- [ ] Multi-stage Docker builds (why 2 stages?)
- [ ] Distroless images (why not use ubuntu/alpine for production?)
- [ ] Health checks vs readiness checks (what's the difference?)
- [ ] Prometheus metrics (what is /metrics endpoint for?)
- [ ] Graceful shutdown (why does the Go code listen for SIGTERM?)

**Interview question you should be able to answer:**
> "How do you optimize Docker images for production? What security considerations do you apply?"

---

### Week 2: Kubernetes Fundamentals

**What to learn:**
- Pods, Deployments, Services, ConfigMaps, Secrets
- How Kubernetes keeps apps running (self-healing)
- Resource requests/limits and why they matter
- Namespaces for isolation

**Files to study:**
```
kubernetes/base/namespace.yaml
kubernetes/base/configmap.yaml
kubernetes/base/transaction-api/deployment.yaml
kubernetes/base/transaction-api/service.yaml
kubernetes/base/transaction-api/hpa.yaml
kubernetes/base/resource-quota.yaml
```

**Exercises:**
1. Set up a local cluster with `minikube` or `kind`
2. Deploy the base manifests: `kubectl apply -k kubernetes/base/`
3. Watch pods come up: `kubectl get pods -n finflow -w`
4. Kill a pod and watch it restart: `kubectl delete pod <pod-name> -n finflow`
5. Look at the HPA: `kubectl get hpa -n finflow`

**Key concepts to understand in the deployment.yaml:**
```yaml
# WHY: Tells K8s how much CPU/memory to reserve for this container
resources:
  requests:   # "I need at least this much" — used for scheduling
    cpu: 100m      # 100 millicores = 0.1 CPU
    memory: 128Mi  # 128 megabytes
  limits:     # "Never let me exceed this" — kills pod if exceeded
    cpu: 500m
    memory: 256Mi

# WHY: K8s uses this to know if the pod is alive
livenessProbe:
  httpGet:
    path: /health   # If this returns non-200, K8s restarts the pod
    
# WHY: K8s uses this to know if the pod is ready to receive traffic
readinessProbe:
  httpGet:
    path: /ready    # If this fails, pod is removed from Service endpoints

# WHY: Spread pods across zones so a zone failure doesn't kill all replicas
topologySpreadConstraints:
  - topologyKey: topology.kubernetes.io/zone
```

**Key concepts to research:**
- [ ] What happens when a node dies? (pod rescheduling)
- [ ] Difference between Deployment and StatefulSet
- [ ] What does `kubectl apply -k` do? (Kustomize)
- [ ] What is a Service and how does DNS work in K8s?
- [ ] Why do we need PodDisruptionBudgets?

**Interview question:**
> "Walk me through what happens when you deploy a new version of a service to Kubernetes."

---

## Phase 2: Infrastructure as Code (Weeks 3-5)

### Goal: Provision cloud resources using Terraform

### Week 3: Terraform Basics

**What to learn:**
- HCL syntax (variables, resources, outputs, modules)
- Terraform workflow: init → plan → apply → destroy
- State management (why remote state matters)
- How modules create reusable infrastructure

**Files to study:**
```
terraform/versions.tf                          # Provider versions
terraform/modules/gcp/vpc/main.tf             # VPC module (start here)
terraform/modules/gcp/gke/main.tf             # GKE module
terraform/environments/dev/main.tf            # How modules are composed
terraform/environments/dev/terraform.tfvars.example
```

**Reading order for the GCP VPC module:**
1. Look at the `variable` blocks — what inputs does this module need?
2. Look at the `resource` blocks — what does it create?
3. Look at the `output` blocks — what does it expose to other modules?
4. Notice how `terraform/environments/dev/main.tf` calls `module "gcp_vpc"` and passes variables

**Exercises:**
1. Install Terraform: `brew install terraform`
2. Create a GCP project with free credits
3. Deploy JUST the VPC module to GCP:
   ```bash
   cd terraform/environments/dev
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your project ID
   terraform init
   terraform plan    # READ the plan output carefully
   terraform apply   # Only apply the VPC (comment out other modules)
   ```
4. Look at what was created in GCP Console
5. Run `terraform destroy` to clean up

**Key concept — Module composition:**
```hcl
# environments/dev/main.tf

# First, create the network
module "gcp_vpc" {
  source = "../../modules/gcp/vpc"
  # ...
}

# Then, create GKE cluster INSIDE that network
module "gcp_gke" {
  source = "../../modules/gcp/gke"
  vpc_id    = module.gcp_vpc.vpc_id        # ← Output from VPC becomes input to GKE
  subnet_id = module.gcp_vpc.gke_subnet_id # ← This is how modules connect
}
```

**Key concepts to research:**
- [ ] What is Terraform state? Why store it remotely?
- [ ] What happens if two people run `terraform apply` at the same time?
- [ ] What is a Terraform module? How is it different from a resource?
- [ ] What does `terraform plan` show you?
- [ ] What is "infrastructure drift"?

---

### Week 4: Multi-Cloud Networking

**What to learn:**
- VPC/VNet/VCN — the "private network" in each cloud
- Subnets (public vs private), NAT gateways, route tables
- Why GKE nodes go in private subnets (no public IPs)
- How traffic flows: Internet → Load Balancer → Node → Pod

**Files to study:**
```
terraform/modules/gcp/vpc/main.tf       # GCP networking
terraform/modules/aws/vpc/main.tf       # AWS networking (compare!)
terraform/modules/azure/vnet/main.tf    # Azure networking
terraform/modules/networking/cross-cloud-vpn/main.tf
```

**Compare GCP vs AWS:**
| Concept | GCP | AWS |
|---------|-----|-----|
| Virtual network | VPC | VPC |
| Sub-network | Subnet | Subnet |
| Outbound internet | Cloud NAT | NAT Gateway |
| Firewall | Firewall Rules | Security Groups |
| Private GKE/EKS | Private cluster | Private endpoint |

**Key concept — Why private subnets?**
```
Internet traffic flow:
Internet → Cloud Load Balancer → Private Subnet (nodes) → Pod

Why not public?
- Nodes with public IPs are directly attackable from the internet
- Private nodes can only be reached through the load balancer
- We use Cloud NAT for outbound (pulling images, etc.)
```

**Interview question:**
> "How would you design networking for a multi-cloud deployment that needs cross-cloud service communication?"

---

### Week 5: Terraform Advanced + OPA Policies

**What to learn:**
- Terraform workspaces and environments
- Remote state backends (GCS, S3)
- Policy-as-code with OPA (why it matters for compliance)
- How to prevent bad infrastructure from being deployed

**Files to study:**
```
terraform/policies/general_policies.rego
terraform/policies/network_policies.rego
terraform/policies/gke_policies.rego
```

**Understand OPA policies:**
```rego
# This DENIES any AWS resource that doesn't have required tags
deny[msg] {
    resource := input.resource_changes[_]
    startswith(resource.type, "aws_")
    required := required_tags[_]
    not resource.change.after.tags[required]
    msg := sprintf("Resource '%s' is missing tag: %s", [resource.name, required])
}
```

**Exercise:**
1. Install OPA: `brew install opa`
2. Run `terraform plan -out=plan.tfplan`
3. Convert to JSON: `terraform show -json plan.tfplan > plan.json`
4. Evaluate policies: `opa eval -d terraform/policies/ -i plan.json "data.finflow.general.deny"`

---

## Phase 3: Service Mesh & Networking (Weeks 6-8)

### Goal: Understand Istio, traffic management, and security

### Week 6: Istio Fundamentals

**What is Istio?** 
A service mesh — it adds a sidecar proxy (Envoy) to every pod that handles:
- Encryption between services (mTLS) — without changing application code
- Traffic routing (canary deployments, A/B testing)
- Resilience (retries, timeouts, circuit breaking)
- Observability (metrics, traces) — automatically

**Why does it matter?**
Without Istio, every developer would need to implement retries, circuit breaking, mTLS, and tracing in their application code. With Istio, the mesh handles it transparently.

**Files to study (in this order):**
```
istio/istio-operator.yaml                    # Installation config
istio/traffic/gateway.yaml                   # Entry point for traffic
istio/traffic/virtual-services.yaml          # Traffic routing rules
istio/traffic/destination-rules.yaml         # How to talk to backends
istio/security/peer-authentication.yaml      # mTLS config
```

**Key concept — Traffic flow with Istio:**
```
Client Request
    ↓
Istio Ingress Gateway (the entry point)
    ↓
Gateway resource (defines which hosts/ports to accept)
    ↓
VirtualService (routing rules — where does the request go?)
    ↓
DestinationRule (HOW to talk to the backend — load balancing, circuit breaking)
    ↓
Service Pod (with Envoy sidecar intercepting all traffic)
```

**Key concept — Canary deployment in VirtualService:**
```yaml
# 90% of traffic goes to v1, 10% to v2 (new version)
route:
  - destination:
      host: transaction-api
      subset: v1       # The stable version
    weight: 90
  - destination:
      host: transaction-api
      subset: v2       # The canary (new version)
    weight: 10
```

**Exercise:**
1. Install Istio on your local cluster: `istioctl install --set profile=demo`
2. Label your namespace: `kubectl label namespace finflow istio-injection=enabled`
3. Redeploy pods (they get Envoy sidecars now)
4. Check sidecars: `kubectl get pods -n finflow` (should show 2/2 containers)
5. Look at the Kiali dashboard: `istioctl dashboard kiali`

---

### Week 7: Istio Security & Resilience

**Files to study:**
```
istio/security/authorization-policies.yaml  # Who can talk to whom
istio/resilience/circuit-breaker.yaml       # Protecting from cascading failures
istio/resilience/fault-injection.yaml       # Chaos testing
istio/resilience/retry-timeout.yaml         # Retry policies
```

**Key concept — Zero-trust security:**
```yaml
# Default: DENY ALL traffic in the namespace
spec: {}  # Empty spec = deny everything

# Then explicitly ALLOW only what's needed:
# "Only transaction-api can call payment-processor on POST /api/v1/process"
rules:
  - from:
      - source:
          principals: ["cluster.local/ns/finflow/sa/transaction-api"]
    to:
      - operation:
          methods: ["POST"]
          paths: ["/api/v1/process"]
```

**Key concept — Circuit breaker:**
```yaml
# If payment-processor returns 3 consecutive 5xx errors:
# → Eject that pod from the load balancer for 30 seconds
# → Prevents one bad pod from handling more requests
# → Like a fuse that trips to protect the system
outlierDetection:
  consecutive5xxErrors: 3
  interval: 5s
  baseEjectionTime: 30s
  maxEjectionPercent: 30  # Never eject more than 30% of pods
```

**Interview question:**
> "How would you implement a canary deployment for a critical payment service? How do you automatically rollback if the canary is failing?"

---

### Week 8: HAProxy, Nginx & Load Balancing

**Files to study:**
```
haproxy/haproxy.cfg
nginx/nginx.conf
haproxy/keepalived.conf
nginx/k8s-ingress.yaml
```

**When to use what:**
| Tool | Use Case |
|------|----------|
| Cloud LB | Entry point from internet |
| Nginx Ingress | Kubernetes HTTP routing |
| HAProxy | High-performance TCP/HTTP LB, database proxying |
| Istio Gateway | Service mesh entry point |

**Key concepts in HAProxy:**
```
# ACL = Access Control List (pattern matching)
acl is_payment path_beg /api/v1/transactions
use_backend transaction_api if is_payment

# Stick table = Rate limiting by IP
stick-table type ip size 100k expire 30s store http_req_rate(10s)
http-request deny deny_status 429 if { sc_http_req_rate(0) gt 100 }
# Translation: If an IP makes more than 100 requests in 10 seconds → 429 Too Many Requests
```

---

## Phase 4: CI/CD & GitOps (Weeks 9-10)

### Goal: Understand the full deployment pipeline from code to production

### Week 9: Jenkins & Container Security

**Files to study:**
```
jenkins/Jenkinsfile
jenkins/shared-library/vars/detectChangedServices.groovy
jenkins/shared-library/vars/deployToKubernetes.groovy
```

**The CI/CD flow:**
```
Developer pushes code
    ↓
Jenkins detects which services changed (via git diff)
    ↓
Parallel build: Go services compiled, Python services linted
    ↓
SAST scan (SonarQube finds code quality issues)
    ↓
Docker images built (multi-stage, optimized)
    ↓
Container scan (Trivy finds vulnerable packages)
    ↓
Images pushed to registry (GCR)
    ↓
GitOps manifests updated (image tag in kustomization.yaml)
    ↓
ArgoCD detects change → deploys to cluster
```

**Key concept — GitOps:**
The cluster state is defined in Git. ArgoCD watches the repo and automatically syncs the cluster to match. If someone manually changes something in the cluster, ArgoCD reverts it (self-heal).

---

### Week 10: ArgoCD & Progressive Delivery

**Files to study:**
```
argocd/app-of-apps.yaml
argocd/project.yaml
argocd/apps/transaction-api.yaml
argocd/apps/payment-processor.yaml
argocd/apps/infrastructure.yaml
```

**Key concept — App of Apps:**
```
finflow-platform (root app)
    ├── transaction-api-prod
    ├── payment-processor-prod
    ├── payment-processor-aws
    ├── kafka-cluster
    ├── observability-stack
    ├── istio-config
    └── vault-config
```
One root Application manages all child Applications. Add a new service? Just add a new YAML file in `argocd/apps/`.

**Exercise:**
1. Install ArgoCD: `kubectl create namespace argocd && kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml`
2. Port forward: `kubectl port-forward svc/argocd-server -n argocd 8443:443`
3. Create the app-of-apps: `kubectl apply -f argocd/app-of-apps.yaml`
4. Watch ArgoCD sync your manifests

---

## Phase 5: Data & Events (Weeks 11-12)

### Goal: Understand Kafka, ProxySQL, and data flow

### Week 11: Kafka Event Streaming

**Files to study:**
```
kafka/cluster.yaml
kafka/topics.yaml
kafka/connect.yaml
kafka/users.yaml
```

**Why Kafka?**
Without Kafka: Transaction API calls Payment Processor directly. If Payment Processor is down, the transaction fails.

With Kafka: Transaction API publishes an event. Payment Processor consumes it when ready. If it's down, messages queue up and process when it recovers.

**Key concepts:**
```
Topic: A category of messages (like "transactions.created")
Partition: A topic is split into partitions for parallelism
  - 12 partitions = 12 consumers can read in parallel
Replication Factor: How many copies of each partition exist
  - RF=3 means data survives 2 broker failures
Consumer Group: A group of consumers that share the work
  - Each partition is read by exactly one consumer in the group
```

**Interview question:**
> "How would you design a Kafka topic for high-throughput transaction processing? What partition count and replication factor would you choose and why?"

---

### Week 12: Database Proxy & MySQL

**Files to study:**
```
proxysql/proxysql.cnf
mysql/schema.sql
terraform/modules/gcp/cloud-sql/main.tf
```

**Why ProxySQL?**
Your app connects to ProxySQL (not directly to MySQL). ProxySQL then:
- Routes SELECTs to replicas (read scaling)
- Routes INSERT/UPDATE/DELETE to the primary (write consistency)
- Caches frequent queries (faster reads)
- Pools connections (don't overwhelm the database)
- Auto-failovers if primary dies

---

## Phase 6: Security & Observability (Weeks 13-14)

### Week 13: Vault Secrets Management

**Files to study:**
```
vault/helm-values.yaml
vault/config/setup.sh
vault/policies/finflow-services.hcl
vault/kubernetes/vault-agent-config.yaml
```

**Why Vault?**
- No hardcoded passwords (dynamic credentials that rotate automatically)
- Each service gets different database credentials
- Credentials expire after 1 hour (if leaked, limited damage)
- Audit trail of who accessed what secrets

**Key concept — Dynamic database credentials:**
```
1. Pod starts → Vault Agent requests credentials
2. Vault creates a temporary MySQL user: "v-txn-api-abc123" with password "random-xyz"
3. App uses those credentials for 1 hour
4. After 1 hour, Vault revokes the user and creates a new one
5. If credentials are leaked, they expire automatically
```

---

### Week 14: Observability (Prometheus + Grafana + Jaeger)

**Files to study:**
```
observability/prometheus/alerts.yaml
observability/prometheus/prometheus-values.yaml
observability/grafana/dashboards/finflow-overview.json
observability/jaeger/jaeger.yaml
observability/loki/loki-values.yaml
```

**The three pillars of observability:**
| Pillar | Tool | What it tells you |
|--------|------|-------------------|
| Metrics | Prometheus + Grafana | "How is the system performing?" (rates, latencies, errors) |
| Logs | Loki | "What happened?" (detailed event records) |
| Traces | Jaeger | "Where did time go?" (request path across services) |

**Key concept — Prometheus alerting:**
```yaml
# "If more than 5% of requests return 5xx for 2 minutes, fire a critical alert"
- alert: HighErrorRate
  expr: sum(rate(http_requests_total{status=~"5.*"}[5m])) / sum(rate(http_requests_total[5m])) > 0.05
  for: 2m
  labels:
    severity: critical
```

---

## Phase 7: Advanced Topics (Weeks 15-16)

### Week 15: Multi-Cluster & DR

**Files to study:**
```
istio/multi-cluster/setup.sh
istio/multi-cluster/gcp-primary-config.yaml
istio/multi-cluster/aws-secondary-config.yaml
dr/disaster-recovery-plan.md
scripts/failover.sh
scripts/chaos-test.sh
```

**Key concepts:**
- Locality-aware load balancing (prefer local cluster, failover to remote)
- Database replication across regions
- DNS-based failover (update DNS to point to secondary)
- RPO (how much data can you lose) vs RTO (how long can you be down)

---

### Week 16: Ansible & Putting It All Together

**Files to study:**
```
ansible/playbooks/site.yaml
ansible/roles/common/tasks/main.yaml
ansible/roles/security-hardening/tasks/main.yaml
ansible/roles/haproxy/tasks/main.yaml
ansible/inventory/gcp.yaml
```

**When Terraform vs Ansible?**
| | Terraform | Ansible |
|--|-----------|---------|
| Creates | Infrastructure (VMs, networks, databases) | Configures what's inside the VM |
| Example | Create an EC2 instance | Install Nginx on that instance |
| State | Tracks state file | Stateless (runs tasks) |
| Approach | Declarative ("I want 3 servers") | Procedural ("Do step 1, then step 2") |

---

## Study Tips for the Interview

### What senior engineers are expected to know:

1. **Trade-offs** — Not just "I used X" but "I chose X over Y because of Z trade-off"
2. **Failure modes** — "What happens when this component fails?"
3. **Scale** — "How does this handle 10x traffic?"
4. **Cost** — "How do you optimize cloud spend?"
5. **Security** — "How do you prevent unauthorized access?"

### Questions to practice:

1. "Design a multi-region deployment for a payment system. Walk me through the architecture."
2. "A service is returning 503 errors. How do you troubleshoot?"
3. "How would you implement zero-downtime deployments?"
4. "Explain how you'd set up secrets management for a Kubernetes cluster."
5. "How do you handle database migrations in a containerized environment?"
6. "What's your approach to monitoring and alerting? How do you reduce alert fatigue?"

### Resources to supplement this repo:

- **Kubernetes:** [kubernetes.io/docs](https://kubernetes.io/docs/) (official docs are excellent)
- **Terraform:** [developer.hashicorp.com/terraform](https://developer.hashicorp.com/terraform/tutorials)
- **Istio:** [istio.io/latest/docs](https://istio.io/latest/docs/)
- **Kafka:** Confluent's free courses at [developer.confluent.io](https://developer.confluent.io)
- **Vault:** [developer.hashicorp.com/vault](https://developer.hashicorp.com/vault/tutorials)

---

## Progress Tracker

Use this to track your learning:

- [ ] Phase 1: Can build and run containers, deploy to K8s
- [ ] Phase 2: Can provision infrastructure with Terraform
- [ ] Phase 3: Can explain Istio traffic flow and security
- [ ] Phase 4: Can set up a CI/CD pipeline end-to-end
- [ ] Phase 5: Can explain Kafka event-driven architecture
- [ ] Phase 6: Can configure Vault and Prometheus/Grafana
- [ ] Phase 7: Can design multi-cluster DR and explain trade-offs
- [ ] Can explain the FULL system architecture in 5 minutes
- [ ] Can answer "what happens when X fails?" for every component
