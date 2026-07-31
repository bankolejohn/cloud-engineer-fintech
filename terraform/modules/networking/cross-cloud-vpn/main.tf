# ==============================================================================
# Cross-Cloud VPN Module
# VPN tunnels between GCP and AWS for multi-cloud connectivity
# ==============================================================================

variable "environment" {
  description = "Environment name"
  type        = string
}

# GCP Variables
variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "gcp_vpc_id" {
  description = "GCP VPC network ID"
  type        = string
}

variable "gcp_vpc_cidr" {
  description = "GCP VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

# AWS Variables
variable "aws_vpc_id" {
  description = "AWS VPC ID"
  type        = string
}

variable "aws_vpc_cidr" {
  description = "AWS VPC CIDR"
  type        = string
  default     = "10.10.0.0/16"
}

variable "aws_route_table_ids" {
  description = "AWS route table IDs to add VPN routes to"
  type        = list(string)
}

variable "shared_secret" {
  description = "Pre-shared key for VPN tunnels"
  type        = string
  sensitive   = true
}

locals {
  name_prefix = "finflow-${var.environment}"
}

# ==============================================================================
# GCP Side - HA VPN Gateway
# ==============================================================================

# GCP HA VPN Gateway
resource "google_compute_ha_vpn_gateway" "to_aws" {
  name    = "${local.name_prefix}-vpn-to-aws"
  project = var.gcp_project_id
  region  = var.gcp_region
  network = var.gcp_vpc_id
}

# GCP Cloud Router for BGP
resource "google_compute_router" "vpn" {
  name    = "${local.name_prefix}-vpn-router"
  project = var.gcp_project_id
  region  = var.gcp_region
  network = var.gcp_vpc_id

  bgp {
    asn               = 65001
    advertise_mode    = "CUSTOM"
    advertised_groups = ["ALL_SUBNETS"]
  }
}

# GCP VPN Tunnels (2 for HA)
resource "google_compute_vpn_tunnel" "to_aws_1" {
  name                  = "${local.name_prefix}-vpn-tunnel-aws-1"
  project               = var.gcp_project_id
  region                = var.gcp_region
  vpn_gateway           = google_compute_ha_vpn_gateway.to_aws.id
  vpn_gateway_interface = 0
  peer_external_gateway = google_compute_external_vpn_gateway.aws.id
  peer_external_gateway_interface = 0
  shared_secret         = var.shared_secret
  router                = google_compute_router.vpn.id
  ike_version           = 2
}

resource "google_compute_vpn_tunnel" "to_aws_2" {
  name                  = "${local.name_prefix}-vpn-tunnel-aws-2"
  project               = var.gcp_project_id
  region                = var.gcp_region
  vpn_gateway           = google_compute_ha_vpn_gateway.to_aws.id
  vpn_gateway_interface = 1
  peer_external_gateway = google_compute_external_vpn_gateway.aws.id
  peer_external_gateway_interface = 1
  shared_secret         = var.shared_secret
  router                = google_compute_router.vpn.id
  ike_version           = 2
}

# External VPN Gateway (represents AWS side in GCP)
resource "google_compute_external_vpn_gateway" "aws" {
  name            = "${local.name_prefix}-aws-vpn-gw"
  project         = var.gcp_project_id
  redundancy_type = "TWO_IPS_REDUNDANCY"

  interface {
    id         = 0
    ip_address = aws_vpn_connection.to_gcp.tunnel1_address
  }

  interface {
    id         = 1
    ip_address = aws_vpn_connection.to_gcp.tunnel2_address
  }
}

# BGP Router Interfaces
resource "google_compute_router_interface" "vpn_1" {
  name       = "${local.name_prefix}-vpn-interface-1"
  project    = var.gcp_project_id
  region     = var.gcp_region
  router     = google_compute_router.vpn.name
  ip_range   = "169.254.0.1/30"
  vpn_tunnel = google_compute_vpn_tunnel.to_aws_1.name
}

resource "google_compute_router_interface" "vpn_2" {
  name       = "${local.name_prefix}-vpn-interface-2"
  project    = var.gcp_project_id
  region     = var.gcp_region
  router     = google_compute_router.vpn.name
  ip_range   = "169.254.0.5/30"
  vpn_tunnel = google_compute_vpn_tunnel.to_aws_2.name
}

# BGP Peers
resource "google_compute_router_peer" "aws_1" {
  name                      = "${local.name_prefix}-bgp-aws-1"
  project                   = var.gcp_project_id
  region                    = var.gcp_region
  router                    = google_compute_router.vpn.name
  peer_ip_address           = "169.254.0.2"
  peer_asn                  = 65002
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.vpn_1.name
}

resource "google_compute_router_peer" "aws_2" {
  name                      = "${local.name_prefix}-bgp-aws-2"
  project                   = var.gcp_project_id
  region                    = var.gcp_region
  router                    = google_compute_router.vpn.name
  peer_ip_address           = "169.254.0.6"
  peer_asn                  = 65002
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.vpn_2.name
}

# ==============================================================================
# AWS Side - VPN Gateway
# ==============================================================================

# AWS VPN Gateway
resource "aws_vpn_gateway" "main" {
  vpc_id          = var.aws_vpc_id
  amazon_side_asn = 65002

  tags = {
    Name        = "${local.name_prefix}-vpn-gw"
    Environment = var.environment
    Project     = "finflow"
  }
}

# AWS Customer Gateway (represents GCP side)
resource "aws_customer_gateway" "gcp" {
  bgp_asn    = 65001
  ip_address = google_compute_ha_vpn_gateway.to_aws.vpn_interfaces[0].ip_address
  type       = "ipsec.1"

  tags = {
    Name        = "${local.name_prefix}-cgw-gcp"
    Environment = var.environment
    Project     = "finflow"
  }
}

# AWS VPN Connection
resource "aws_vpn_connection" "to_gcp" {
  vpn_gateway_id      = aws_vpn_gateway.main.id
  customer_gateway_id = aws_customer_gateway.gcp.id
  type                = "ipsec.1"
  static_routes_only  = false

  tunnel1_preshared_key = var.shared_secret
  tunnel2_preshared_key = var.shared_secret

  tags = {
    Name        = "${local.name_prefix}-vpn-to-gcp"
    Environment = var.environment
    Project     = "finflow"
  }
}

# VPN Gateway Route Propagation
resource "aws_vpn_gateway_route_propagation" "main" {
  count          = length(var.aws_route_table_ids)
  vpn_gateway_id = aws_vpn_gateway.main.id
  route_table_id = var.aws_route_table_ids[count.index]
}

# Outputs
output "gcp_vpn_gateway_ip_0" {
  value = google_compute_ha_vpn_gateway.to_aws.vpn_interfaces[0].ip_address
}

output "gcp_vpn_gateway_ip_1" {
  value = google_compute_ha_vpn_gateway.to_aws.vpn_interfaces[1].ip_address
}

output "aws_vpn_gateway_id" {
  value = aws_vpn_gateway.main.id
}

output "vpn_connection_id" {
  value = aws_vpn_connection.to_gcp.id
}
