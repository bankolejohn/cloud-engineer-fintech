# Terraform Multi-Cloud — Deep Dive

> How modular Terraform provisions infrastructure across GCP, AWS, Azure, and OCI from a single codebase.

---

## What Terraform Does (One Line)

Describes infrastructure in code files and creates/updates/destroys it across any cloud provider.

---

## The Workflow

```
1. WRITE (main.tf)     → "I want a VPC with 3 subnets"
2. PLAN (terraform plan) → "Here's what I'll create: +vpc, +subnet-a, +subnet-b, +subnet-c"
3. APPLY (terraform apply) → Creates everything in the cloud
4. STATE (terraform.tfstate) → Remembers what exists (for next plan/apply)
```

---

## Repo Structure

```
terraform/
├── modules/              ← REUSABLE building blocks (like functions)
│   ├── gcp/vpc/         ← GCP network module
│   ├── gcp/gke/        ← GCP Kubernetes module
│   ├── aws/vpc/         ← AWS network module
│   ├── aws/eks/         ← AWS Kubernetes module
│   └── ...
├── environments/         ← COMPOSED configurations (like main programs)
│   ├── dev/main.tf      ← Dev: GCP + AWS (small)
│   └── prod/main.tf     ← Prod: GCP + AWS + Azure + OCI (full)
└── policies/             ← OPA compliance rules
```

Modules = LEGO bricks. Environments = assembled models.

---

## How Modules Connect (The Key Concept)

```hcl
# Step 1: Create the network
module "gcp_vpc" {
  source = "../../modules/gcp/vpc"
  project_id = "finflow-prod"
}
# Outputs: vpc_id, gke_subnet_id, pods_range_name, services_range_name

# Step 2: Create GKE INSIDE that network
module "gcp_gke" {
  source    = "../../modules/gcp/gke"
  vpc_id    = module.gcp_vpc.vpc_id              ← OUTPUT from VPC becomes INPUT to GKE
  subnet_id = module.gcp_vpc.gke_subnet_id       ← This is how modules connect
}

# Step 3: Create MySQL in the same network
module "gcp_cloud_sql" {
  source = "../../modules/gcp/cloud-sql"
  vpc_id = module.gcp_vpc.vpc_id                 ← Same VPC = they can communicate
}
```

Terraform automatically determines order:
1. VPC first (no dependencies)
2. GKE and Cloud SQL in parallel (both depend only on VPC)

---

## Multi-Cloud: Same Pattern, Different Providers

```hcl
# GCP (Primary)
module "gcp_vpc" { source = "../../modules/gcp/vpc"; vpc_cidr = "10.0.0.0/16" }
module "gcp_gke" { vpc_id = module.gcp_vpc.vpc_id }

# AWS (Secondary) — SAME PATTERN
module "aws_vpc" { source = "../../modules/aws/vpc"; vpc_cidr = "10.10.0.0/16" }
module "aws_eks" { vpc_id = module.aws_vpc.vpc_id }

# Azure (EU Compliance) — SAME PATTERN
module "azure_vnet" { source = "../../modules/azure/vnet"; vnet_cidr = "10.20.0.0/16" }
module "azure_aks"  { vnet_subnet_id = module.azure_vnet.aks_subnet_id }

# OCI (Batch Processing) — SAME PATTERN
module "oci_vcn" { source = "../../modules/oci/vcn"; vcn_cidr = "10.30.0.0/16" }
module "oci_oke" { vcn_id = module.oci_vcn.vcn_id }
```

The pattern for every cloud:
1. Create network (VPC/VNet/VCN)
2. Create Kubernetes (GKE/EKS/AKS/OKE) inside that network
3. Create database inside that network
4. Connect networks together (VPN)

---

## IP Address Design (Non-Overlapping CIDRs)

```
Cloud    CIDR             Purpose
─────    ──────────       ───────
GCP      10.0.0.0/16     GKE nodes
GCP      10.1.0.0/16     GKE pods
GCP      10.2.0.0/20     GKE services
GCP      10.3.0.0/24     Databases
AWS      10.10.0.0/16    EKS nodes + databases
Azure    10.20.0.0/16    AKS nodes
OCI      10.30.0.0/16    OKE nodes

NONE overlap — required for VPN routing between clouds.
Request to 10.0.x.x → GCP.  Request to 10.10.x.x → AWS.
```

---

## Cross-Cloud VPN

```
GCP (10.0.0.0/16) ←══ Encrypted IPsec Tunnel ══→ AWS (10.10.0.0/16)
     HA VPN Gateway         BGP routing          AWS VPN Gateway
     ASN: 65001                                  ASN: 65002

After VPN established:
- GKE pod (10.1.5.20) can reach AWS RDS (10.10.200.10) directly
- EKS pod can reach GCP Cloud SQL (10.3.0.10) directly
- BGP auto-advertises routes (each side knows how to reach the other)
```

---

## Dev vs Prod — Same Modules, Different Sizes

```hcl
# Dev: Small and cheap
module "gcp_gke" {
  machine_type = "e2-standard-2"    # 2 vCPU
  node_count   = 1
  max_nodes    = 3
}

# Prod: Large and resilient
module "gcp_gke" {
  machine_type = "e2-standard-4"    # 4 vCPU
  node_count   = 3                  # One per zone
  max_nodes    = 10
}
```

Same module. Different variables. Identical logic.

---

## State Management

State file records what exists. Stored remotely (GCS bucket):
```hcl
backend "gcs" {
  bucket = "finflow-terraform-state"
  prefix = "environments/dev"    # Each env has isolated state
}
```

Why remote: Shared team access, backup, locking (prevents concurrent applies).

---

## OPA Policies (Guard Rails)

```rego
# Block expensive instances in dev
deny[msg] {
    resource := input.resource_changes[_]
    contains(resource.name, "dev")
    resource.change.after.instance_type == "m5.4xlarge"
    msg := "Can't use m5.4xlarge in dev — too expensive!"
}
```

Evaluated in CI before apply. Violations = deploy blocked.

---

## Key Files in This Repo

```
terraform/versions.tf                          → Provider version pins
terraform/modules/gcp/vpc/main.tf             → GCP networking
terraform/modules/gcp/gke/main.tf             → GCP Kubernetes
terraform/modules/aws/vpc/main.tf             → AWS networking
terraform/modules/aws/eks/main.tf             → AWS Kubernetes
terraform/modules/azure/vnet/main.tf          → Azure networking
terraform/modules/azure/aks/main.tf           → Azure Kubernetes
terraform/modules/oci/vcn/main.tf             → OCI networking
terraform/modules/oci/oke/main.tf             → OCI Kubernetes
terraform/modules/networking/cross-cloud-vpn/ → GCP↔AWS VPN
terraform/environments/dev/main.tf            → Dev composition
terraform/environments/prod/main.tf           → Prod composition (all 4 clouds)
terraform/policies/*.rego                     → Compliance policies
```

---

## Who Designs the Network? (Roles & Responsibilities)

At Moniepoint's scale (mid-size, 50-200 engineers), the **Cloud Engineer** (this role) designs AND implements the networking:

| Decision | Who |
|----------|-----|
| CIDR layout (non-overlapping per cloud) | You (Cloud Engineer) |
| Public vs private subnet segmentation | You |
| Firewall rules / security groups | You (with requirements from Security team) |
| VPN/Interconnect between clouds | You |
| Documentation and architecture diagrams | You |

Security team says: "PCI-DSS requires cardholder data in isolated networks."
You translate that into: private subnet + security group allowing only port 3306 from the app subnet.

---

## How You Design a Network (The Thinking Process)

### Step 1: Capacity Planning

```
"How many IPs do I need?"

GKE cluster:
  - 10 nodes max → 10 IPs
  - 110 pods/node × 10 nodes = 1,100 pod IPs
  - 200 K8s services → 200 IPs
  - Databases, LBs → 50 IPs

Total: ~1,400 IPs for GCP alone
  /16 = 65,536 IPs (plenty of room to grow) ← Choose this
  /20 = 4,096 IPs (might run out in 2 years)

Rule: Always go bigger. CIDRs cost nothing. Running out of IPs costs re-architecting.
```

### Step 2: Security Zones (Defense in Depth)

```
PUBLIC zone (internet-facing):
  └── Load balancers ONLY. Nothing else gets a public IP.

PRIVATE zone (no inbound internet):
  └── GKE/EKS nodes (app pods live here)
  └── Outbound via NAT (pull Docker images)
  └── Attacker from internet can't reach these directly

DATABASE zone (most restricted):
  └── Only reachable from PRIVATE zone (app nodes)
  └── No internet access (inbound OR outbound)
  └── Separate subnet = separate firewall rules

Even if attacker compromises a pod → can't reach the database
because network-level rules block it (not just application logic).
```

### Step 3: Multi-Cloud Layout (Non-Overlapping)

```
Simple rule: Each cloud gets its own second octet.

10.0.x.x   = GCP
10.10.x.x  = AWS
10.20.x.x  = Azure
10.30.x.x  = OCI

Within each cloud:
  10.0.0.0/20   = Nodes (subnet A, zone-a)
  10.0.16.0/20  = Nodes (subnet B, zone-b)
  10.0.200.0/24 = Databases
  10.1.0.0/16   = Pod IPs (secondary range)
  10.2.0.0/20   = Service IPs (secondary range)

Why non-overlapping matters:
  VPN router sees packet to 10.0.1.5 → sends to GCP
  VPN router sees packet to 10.10.1.5 → sends to AWS
  If both used 10.0.0.0/16 → router can't tell them apart → broken routing
```

### Step 4: Connectivity Rules

```
Within same cloud:  Same VPC can communicate (default)
Cross-cloud:        VPN only, specific ports only

Security group rules (allowlist pattern):
  Database SG:     Allow port 3306 from app subnet ONLY
  App SG:          Allow ports 8080-8084 from load balancer ONLY
  Load balancer:   Allow port 443 from internet (0.0.0.0/0)
  Everything else: DENIED by default
```

---

## Interview Answer Template

> "How would you design networking for a multi-cloud deployment?"

1. Non-overlapping CIDRs per cloud (for VPN routing)
2. Three-tier subnets: public (LB), private (compute), database (isolated)
3. Cloud NAT for outbound from private subnets
4. HA VPN with BGP between clouds (automatic route exchange)
5. Security groups as strict allowlists (deny-all default)
6. VPC Flow Logs enabled (audit + troubleshooting)
7. Everything documented in architecture diagrams and IP allocation table
