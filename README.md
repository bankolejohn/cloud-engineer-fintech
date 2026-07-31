# FinFlow — Multi-Cloud Financial Transaction Processing Platform

A production-grade, multi-cloud fintech platform demonstrating end-to-end cloud engineering practices: infrastructure as code, container orchestration, service mesh, event-driven architecture, CI/CD, secrets management, and full observability.

## Architecture Overview

```
                    ┌─────────────────────────────────────────────────┐
                    │              Global Traffic Management            │
                    │         (Nginx/HAProxy + Cloud Load Balancers)    │
                    └──────────────┬──────────────────┬────────────────┘
                                   │                  │
                 ┌─────────────────▼──┐         ┌────▼─────────────────┐
                 │   GCP (Primary)     │         │   AWS (Secondary)     │
                 │   GKE Cluster       │         │   EKS Cluster         │
                 │   + Istio Mesh      │         │   + Istio Mesh        │
                 └────────┬────────────┘         └────────┬─────────────┘
                          │                               │
                 ┌────────▼────────────────────────────────▼─────────────┐
                 │              Istio Multi-Cluster Service Mesh           │
                 │   (mTLS, traffic splitting, canary, circuit breaking)   │
                 └────────┬────────────────────────────────┬─────────────┘
                          │                               │
          ┌───────────────▼───────────────┐  ┌───────────▼──────────────┐
          │  Microservices                 │  │  Event Infrastructure     │
          │  - Transaction API (Go)        │  │  - Kafka Cluster           │
          │  - Payment Processor (Go)      │  │  - Event Router            │
          │  - Fraud Detection (Python)    │  │  - Notification Service    │
          │  - Account Service (Go)        │  │                            │
          └───────────────┬───────────────┘  └───────────┬──────────────┘
                          │                               │
          ┌───────────────▼───────────────────────────────▼──────────────┐
          │                    Data Layer                                  │
          │  MySQL (ProxySQL) + Vault (Secrets) + Cloud Storage            │
          └──────────────────────────────────────────────────────────────┘
```

## Technology Stack

| Category | Technologies |
|----------|-------------|
| Cloud Providers | GCP, AWS, Azure, OCI |
| Container Orchestration | Kubernetes (GKE, EKS, AKS, OKE) |
| Service Mesh | Istio |
| Reverse Proxy / LB | HAProxy, Nginx |
| Infrastructure as Code | Terraform, Ansible |
| CI/CD | Jenkins, Harness, ArgoCD |
| Event Streaming | Apache Kafka (Strimzi) |
| Database | MySQL + ProxySQL |
| Secrets Management | HashiCorp Vault |
| Observability | Prometheus, Grafana, Loki, Jaeger |
| Languages | Go, Python, Bash |

## Repository Structure

```
finflow-platform/
├── services/                 # Application microservices
│   ├── transaction-api/      # Payment initiation REST API (Go)
│   ├── payment-processor/    # Payment validation & processing (Go)
│   ├── fraud-detection/      # Transaction fraud scoring (Python)
│   ├── account-service/      # Account management (Go)
│   └── notification-service/ # Payment notifications (Python)
├── terraform/                # Multi-cloud infrastructure as code
│   ├── modules/              # Reusable modules (gcp, aws, azure, oci, networking)
│   ├── environments/         # Environment configurations (dev, staging, prod)
│   └── policies/             # OPA/Sentinel policy-as-code
├── kubernetes/               # K8s manifests
│   ├── base/                 # Kustomize base resources
│   └── overlays/             # Per-environment overlays
├── helm/charts/              # Helm charts for services
├── docker/                   # Dockerfiles for all services
├── istio/                    # Service mesh configuration
│   ├── traffic/              # VirtualServices, DestinationRules
│   ├── security/             # mTLS, AuthorizationPolicies
│   ├── resilience/           # Circuit breakers, fault injection
│   └── multi-cluster/        # Cross-cluster mesh config
├── haproxy/                  # HAProxy load balancer configs
├── nginx/                    # Nginx reverse proxy configs
├── jenkins/                  # Jenkins pipelines & shared libraries
├── harness/                  # Harness deployment pipelines
├── argocd/                   # ArgoCD GitOps app definitions
├── kafka/                    # Kafka cluster & topic configs
├── proxysql/                 # ProxySQL database proxy configs
├── mysql/                    # Database schemas & replication
├── vault/                    # HashiCorp Vault setup
├── observability/            # Monitoring & logging stack
│   ├── prometheus/           # Metrics & alerting
│   ├── grafana/              # Dashboards
│   ├── loki/                 # Log aggregation
│   └── jaeger/               # Distributed tracing
├── ansible/                  # Configuration management
│   ├── playbooks/            # Provisioning playbooks
│   ├── roles/                # Reusable roles
│   └── inventory/            # Dynamic inventory configs
├── dr/                       # Disaster recovery & chaos testing
├── scripts/                  # Helper scripts (Python/Bash)
└── docs/                     # Architecture docs, ADRs, runbooks
```

## Getting Started

### Prerequisites

- Terraform >= 1.5
- kubectl >= 1.28
- Helm >= 3.12
- Docker >= 24.0
- Go >= 1.21
- Python >= 3.11
- Ansible >= 2.15
- istioctl >= 1.20
- ArgoCD CLI >= 2.9
- Vault CLI >= 1.15
- Cloud CLIs: gcloud, aws, az, oci

### Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/yourusername/finflow-platform.git
cd finflow-platform

# 2. Set up cloud credentials
cp .env.example .env
# Edit .env with your cloud credentials

# 3. Deploy infrastructure (start with dev)
cd terraform/environments/dev
terraform init
terraform plan
terraform apply

# 4. Configure Kubernetes access
gcloud container clusters get-credentials finflow-gke --region us-central1
aws eks update-kubeconfig --name finflow-eks --region us-east-1

# 5. Install Istio service mesh
istioctl install -f istio/istio-operator.yaml

# 6. Deploy services via ArgoCD
kubectl apply -f argocd/app-of-apps.yaml

# 7. Deploy observability stack
helm install prometheus observability/prometheus/
helm install grafana observability/grafana/
```

## Key Features Demonstrated

### Multi-Cloud Architecture
- Active-active deployment across GCP (primary) and AWS (secondary)
- Cross-cloud VPN connectivity and service discovery
- Cloud-agnostic Terraform modules with provider abstraction
- Disaster recovery with automated failover between clouds

### Service Mesh (Istio)
- Mutual TLS between all services
- Canary deployments with traffic splitting (90/10 → 50/50 → 100)
- Circuit breaking and retry policies
- Fault injection for chaos engineering
- Multi-cluster mesh spanning GCP and AWS

### Event-Driven Architecture
- Kafka-based event streaming for transaction processing
- CDC (Change Data Capture) with Debezium for MySQL
- Dead letter queues for failed event processing
- Schema registry for event contract management

### GitOps & CI/CD
- Jenkins for build and test pipelines
- ArgoCD for declarative Kubernetes deployments
- Harness for multi-stage deployment with approvals
- Progressive delivery (blue-green, canary) via Istio + ArgoCD

### Security
- HashiCorp Vault for all secrets (zero hardcoded credentials)
- Dynamic database credentials with automatic rotation
- mTLS everywhere via Istio
- OPA policies for infrastructure compliance
- Container image scanning in CI pipeline

## Cost Management

This project is designed to be cost-efficient for learning:
- Use cloud free tiers and credits (GCP $300, Azure $200, AWS free tier, OCI always-free)
- Terraform makes it easy to `destroy` when not in use
- Smallest viable instance sizes for dev environment
- Auto-scaling from zero where possible

## License

MIT
