# FinFlow Glossary — Plain English Explanations

> Every term you'll encounter in this repo, explained like you're explaining to a friend.

---

## Infrastructure

| Term | Plain English |
|------|---------------|
| **VPC** | Your own private network in the cloud. Like having your own floor in a building — no one else can access it unless you let them in. |
| **Subnet** | A smaller section within your VPC. Like rooms on your floor — some are public-facing (lobby) and some are private (server room). |
| **Private Subnet** | A room with no door to the outside. Can only be reached through the lobby (load balancer). |
| **NAT Gateway** | Lets your private servers reach the internet (to download packages, etc.) without being reachable FROM the internet. One-way door. |
| **Security Group / Firewall Rule** | A bouncer at the door. "Only allow traffic on port 443 from these IP addresses." |
| **Load Balancer** | A traffic cop that distributes incoming requests across multiple servers so no single one gets overwhelmed. |
| **VPN** | A private encrypted tunnel between two networks. Like a secret underground passage between two buildings. |
| **CIDR** | A way to write IP address ranges. `10.0.0.0/16` means "all IPs from 10.0.0.0 to 10.0.255.255" (65,536 addresses). |
| **IAM** | Identity and Access Management. Controls WHO can do WHAT in your cloud account. |

---

## Kubernetes

| Term | Plain English |
|------|---------------|
| **Pod** | The smallest deployable unit. Usually one container (your app) running on the cluster. |
| **Deployment** | "I want 3 copies of this pod running at all times." If one dies, K8s makes a new one. |
| **Service** | A stable address (DNS name) that routes to your pods. Pods come and go, but the Service address stays the same. |
| **Namespace** | A folder for organizing resources. Like having `dev/`, `staging/`, `prod/` folders. |
| **ConfigMap** | A file of non-secret configuration (feature flags, URLs). Mounted into your pod. |
| **Secret** | Like ConfigMap but for sensitive data (passwords, API keys). Base64 encoded (not actually encrypted — that's what Vault is for). |
| **HPA** | Horizontal Pod Autoscaler. "If CPU goes above 70%, add more pods. If it drops, remove pods." |
| **PDB** | Pod Disruption Budget. "Always keep at least 1 pod running, even during upgrades." |
| **Ingress** | A set of rules for how external traffic reaches your services. Like a routing table for HTTP. |
| **Node** | A physical/virtual machine that runs your pods. A cluster has many nodes. |
| **Kustomize** | A tool to customize K8s manifests per environment without duplicating files. |
| **Helm** | A package manager for K8s. Like `apt install` but for Kubernetes applications. |

---

## Istio / Service Mesh

| Term | Plain English |
|------|---------------|
| **Service Mesh** | An infrastructure layer that handles service-to-service communication. Adds security, observability, and traffic control without changing app code. |
| **Sidecar** | A helper container that runs alongside your app container in the same pod. Istio's sidecar (Envoy) intercepts all network traffic. |
| **Envoy** | The actual proxy that Istio injects. It sits between your app and the network. |
| **mTLS** | Mutual TLS. Both sides verify each other's identity. Like both people showing ID before sharing information. |
| **VirtualService** | Routing rules. "Send 90% of traffic to v1 and 10% to v2." |
| **DestinationRule** | "When talking to service X, use round-robin load balancing and enable circuit breaking." |
| **Gateway** | The front door of your mesh. Defines how external traffic enters. |
| **Circuit Breaker** | If a service is failing, stop sending it traffic temporarily (like a fuse tripping). Prevents cascading failures. |
| **Canary Deployment** | Ship new version to a small % of users first. If it works, gradually increase. If it fails, roll back. |
| **Fault Injection** | Intentionally cause failures in dev/staging to test resilience. "What happens if this service is slow?" |

---

## CI/CD

| Term | Plain English |
|------|---------------|
| **CI (Continuous Integration)** | Every code push automatically: builds the code, runs tests, checks for issues. |
| **CD (Continuous Deployment)** | After CI passes, code automatically deploys to production (or staging). |
| **Pipeline** | The sequence of steps from code push to deployment. Build → Test → Scan → Deploy. |
| **GitOps** | The cluster state is defined in Git. Change Git = change the cluster. Single source of truth. |
| **ArgoCD** | Watches your Git repo. When manifests change, it syncs the cluster to match. |
| **Blue-Green Deployment** | Run two identical environments. Deploy to "green" while "blue" serves traffic. Swap when ready. Instant rollback = swap back. |
| **SAST** | Static Application Security Testing. Scans your source code for vulnerabilities without running it. |
| **DAST** | Dynamic Application Security Testing. Scans your running application for vulnerabilities. |
| **Container Scanning** | Checks your Docker images for known vulnerable packages (like a CVE database lookup). |

---

## Kafka / Event Streaming

| Term | Plain English |
|------|---------------|
| **Event-Driven Architecture** | Instead of services calling each other directly, they publish events. "Hey, a transaction was created!" Other services react to that event. |
| **Topic** | A named channel for messages. Like a TV channel — producers broadcast, consumers tune in. |
| **Partition** | A topic is split into partitions for parallel processing. More partitions = more consumers can work simultaneously. |
| **Replication Factor** | How many copies of each message exist. RF=3 means the message is on 3 different brokers. |
| **Consumer Group** | A team of consumers that share the work. Each message goes to exactly one member of the group. |
| **Offset** | A bookmark. "I've read up to message #1523." If a consumer restarts, it continues from its offset. |
| **CDC** | Change Data Capture. Watches the database transaction log and publishes every INSERT/UPDATE/DELETE as a Kafka event. |
| **Dead Letter Queue (DLQ)** | Where failed messages go. "I couldn't process this message after 3 retries, so I'll put it aside for investigation." |

---

## Database / ProxySQL

| Term | Plain English |
|------|---------------|
| **Read Replica** | A copy of your database that only handles SELECT queries. Reduces load on the primary. |
| **Read/Write Splitting** | SELECTs go to replicas, INSERT/UPDATE/DELETE go to primary. ProxySQL does this automatically. |
| **Connection Pooling** | Instead of each app creating a new DB connection (expensive), reuse a pool of existing connections. |
| **Replication Lag** | How far behind the replica is from the primary. If primary writes data now, replica might see it 100ms later. |
| **Failover** | When the primary database dies, a replica gets promoted to be the new primary. |

---

## Vault / Security

| Term | Plain English |
|------|---------------|
| **Secrets Management** | A centralized, secure place to store passwords, API keys, and certificates. Never hardcode secrets. |
| **Dynamic Secrets** | Vault creates a temporary username/password on demand. It expires after 1 hour. If leaked, damage is limited. |
| **Secret Engine** | A plugin in Vault that generates/stores specific types of secrets (database creds, AWS keys, certificates). |
| **Transit Engine** | Vault encrypts/decrypts data for you. Your app sends plaintext, gets ciphertext back. Never touches the encryption key. |
| **Auto-Unseal** | Vault starts sealed (locked). Auto-unseal uses a cloud KMS key to automatically unlock it on restart. |
| **Vault Agent** | A sidecar that runs next to your app, fetches secrets from Vault, and writes them to a file your app can read. |

---

## Observability

| Term | Plain English |
|------|---------------|
| **Metrics** | Numbers over time. "Requests per second was 500 at 2:00 PM." (Prometheus) |
| **Logs** | Text records of what happened. "2024-01-15 14:00:01 ERROR: payment failed for txn-123." (Loki) |
| **Traces** | The journey of a single request across services. "This request took 2s: 50ms in API, 1.5s in payment processor, 450ms in DB." (Jaeger) |
| **PromQL** | Prometheus Query Language. How you ask questions about your metrics. |
| **Alert** | "If error rate > 5% for 2 minutes, page the on-call engineer." |
| **Dashboard** | A visual display of metrics. Grafana turns PromQL queries into graphs. |
| **SLO/SLI/SLA** | SLI = what you measure (latency). SLO = your target (p99 < 500ms). SLA = what you promise customers (99.9% uptime). |

---

## Ansible

| Term | Plain English |
|------|---------------|
| **Playbook** | A YAML file that describes tasks to run on servers. "Install Nginx, copy config, start service." |
| **Role** | A reusable collection of tasks. Like a recipe — "apply the haproxy role" installs and configures HAProxy. |
| **Inventory** | The list of servers to manage. Can be static (a file) or dynamic (auto-discovered from cloud). |
| **Idempotent** | Run it once or 100 times, the result is the same. "Ensure nginx is installed" doesn't reinstall it if it's already there. |

---

## General Cloud Engineering

| Term | Plain English |
|------|---------------|
| **Immutable Infrastructure** | Never modify a running server. Replace it with a new one. Like replacing a car part instead of welding it. |
| **Infrastructure as Code (IaC)** | Define your infrastructure in code files (Terraform). Reproducible, reviewable, version-controlled. |
| **12-Factor App** | Design principles for cloud-native apps (config in env vars, stateless processes, disposable containers). |
| **Horizontal Scaling** | Add more instances (scale out). vs Vertical Scaling = make existing instance bigger (scale up). |
| **High Availability (HA)** | System stays running even when parts fail. Usually means redundancy across zones/regions. |
| **RPO** | Recovery Point Objective. "How much data can we afford to lose?" (e.g., 5 minutes of transactions) |
| **RTO** | Recovery Time Objective. "How long can we be down?" (e.g., 15 minutes) |
