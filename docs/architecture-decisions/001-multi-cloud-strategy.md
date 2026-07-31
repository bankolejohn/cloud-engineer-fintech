# ADR-001: Multi-Cloud Strategy

## Status
Accepted

## Context
FinFlow processes financial transactions that require high availability (99.99% uptime), regulatory compliance across regions, and vendor independence. A single cloud provider creates risk of vendor lock-in and single points of failure.

## Decision
We adopt a multi-cloud strategy with:
- **GCP as primary** — GKE for container orchestration, Cloud SQL for primary database
- **AWS as secondary** — EKS for failover cluster, RDS for database replica
- **Azure for compliance** — AKS for EU regulatory requirements
- **OCI for cost optimization** — OKE for batch processing workloads

Cross-cloud connectivity via VPN tunnels with Istio multi-cluster service mesh for service discovery.

## Consequences
- Increased operational complexity (mitigated by Terraform modules and GitOps)
- Higher networking costs for cross-cloud traffic (mitigated by strategic data locality)
- Need for cloud-agnostic abstractions in IaC (achieved via Terraform modules)
- Improved resilience — no single cloud failure takes down the platform
- Regulatory flexibility — can place workloads in required jurisdictions
