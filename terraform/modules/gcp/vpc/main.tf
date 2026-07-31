# ==============================================================================
# GCP VPC Module
# Creates a VPC with subnets, Cloud NAT, and firewall rules for FinFlow
# ==============================================================================

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "Primary CIDR range for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "pods_cidr" {
  description = "Secondary CIDR range for GKE pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "Secondary CIDR range for GKE services"
  type        = string
  default     = "10.2.0.0/20"
}

# VPC Network
resource "google_compute_network" "main" {
  name                            = "finflow-${var.environment}-vpc"
  project                         = var.project_id
  auto_create_subnetworks         = false
  routing_mode                    = "GLOBAL"
  delete_default_routes_on_create = false
}

# Primary subnet for GKE nodes
resource "google_compute_subnetwork" "gke_nodes" {
  name          = "finflow-${var.environment}-gke-nodes"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.main.id
  ip_cidr_range = var.vpc_cidr

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Subnet for databases and internal services
resource "google_compute_subnetwork" "database" {
  name          = "finflow-${var.environment}-database"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.main.id
  ip_cidr_range = "10.3.0.0/24"

  private_ip_google_access = true
}

# Cloud Router for NAT
resource "google_compute_router" "main" {
  name    = "finflow-${var.environment}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.main.id

  bgp {
    asn = 64514
  }
}

# Cloud NAT for outbound internet access from private nodes
resource "google_compute_router_nat" "main" {
  name                               = "finflow-${var.environment}-nat"
  project                            = var.project_id
  router                             = google_compute_router.main.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall: Allow internal communication
resource "google_compute_firewall" "internal" {
  name    = "finflow-${var.environment}-allow-internal"
  project = var.project_id
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.vpc_cidr, var.pods_cidr, var.services_cidr]
}

# Firewall: Allow health checks from GCP load balancers
resource "google_compute_firewall" "health_checks" {
  name    = "finflow-${var.environment}-allow-health-checks"
  project = var.project_id
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080", "8081", "8082", "8083", "8084"]
  }

  # GCP health check ranges
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["gke-node"]
}

# Firewall: Deny all ingress by default (explicit)
resource "google_compute_firewall" "deny_all_ingress" {
  name     = "finflow-${var.environment}-deny-all-ingress"
  project  = var.project_id
  network  = google_compute_network.main.id
  priority = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}

# Private Service Connection for Cloud SQL
resource "google_compute_global_address" "private_ip_range" {
  name          = "finflow-${var.environment}-private-ip"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_service" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

# Outputs
output "vpc_id" {
  value = google_compute_network.main.id
}

output "vpc_name" {
  value = google_compute_network.main.name
}

output "gke_subnet_id" {
  value = google_compute_subnetwork.gke_nodes.id
}

output "gke_subnet_name" {
  value = google_compute_subnetwork.gke_nodes.name
}

output "database_subnet_id" {
  value = google_compute_subnetwork.database.id
}

output "pods_secondary_range_name" {
  value = "pods"
}

output "services_secondary_range_name" {
  value = "services"
}
