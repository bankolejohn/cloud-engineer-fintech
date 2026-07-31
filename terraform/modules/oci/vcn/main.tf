# ==============================================================================
# OCI VCN Module
# Virtual Cloud Network with subnets, security lists, and NAT for FinFlow
# ==============================================================================

variable "compartment_id" {
  description = "OCI compartment OCID"
  type        = string
}

variable "region" {
  description = "OCI region"
  type        = string
  default     = "us-ashburn-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vcn_cidr" {
  description = "VCN CIDR block"
  type        = string
  default     = "10.30.0.0/16"
}

locals {
  name_prefix = "finflow-${var.environment}"
}

# VCN
resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  display_name   = "${local.name_prefix}-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = "finflow${var.environment}"

  freeform_tags = {
    Environment = var.environment
    Project     = "finflow"
    ManagedBy   = "terraform"
  }
}

# Internet Gateway
resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-igw"
  enabled        = true
}

# NAT Gateway
resource "oci_core_nat_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-nat-gw"
}

# Service Gateway (for OCI services without internet)
resource "oci_core_service_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-svc-gw"

  services {
    service_id = data.oci_core_services.all.services[0].id
  }
}

data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

# Public Subnet (load balancers)
resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  display_name               = "${local.name_prefix}-public-subnet"
  cidr_block                 = cidrsubnet(var.vcn_cidr, 8, 1) # 10.30.1.0/24
  dns_label                  = "pub"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public.id]
}

# Private Subnet (OKE worker nodes)
resource "oci_core_subnet" "oke_nodes" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  display_name               = "${local.name_prefix}-oke-nodes-subnet"
  cidr_block                 = cidrsubnet(var.vcn_cidr, 4, 1) # 10.30.16.0/20
  dns_label                  = "okenodes"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.oke_nodes.id]
}

# Private Subnet (OKE pods)
resource "oci_core_subnet" "oke_pods" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  display_name               = "${local.name_prefix}-oke-pods-subnet"
  cidr_block                 = cidrsubnet(var.vcn_cidr, 2, 1) # 10.30.64.0/18
  dns_label                  = "okepods"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.oke_nodes.id]
}

# Route Tables
resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-public-rt"

  route_rules {
    network_entity_id = oci_core_internet_gateway.main.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-private-rt"

  route_rules {
    network_entity_id = oci_core_nat_gateway.main.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }

  route_rules {
    network_entity_id = oci_core_service_gateway.main.id
    destination       = data.oci_core_services.all.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
  }
}

# Security Lists
resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-public-sl"

  ingress_security_rules {
    protocol  = "6" # TCP
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 443
      max = 443
    }
  }

  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 80
      max = 80
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
  }
}

resource "oci_core_security_list" "oke_nodes" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-oke-nodes-sl"

  # Allow all internal VCN traffic
  ingress_security_rules {
    protocol  = "all"
    source    = var.vcn_cidr
    stateless = false
  }

  # Allow K8s API from control plane
  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
  }
}

# Outputs
output "vcn_id" {
  value = oci_core_vcn.main.id
}

output "public_subnet_id" {
  value = oci_core_subnet.public.id
}

output "oke_nodes_subnet_id" {
  value = oci_core_subnet.oke_nodes.id
}

output "oke_pods_subnet_id" {
  value = oci_core_subnet.oke_pods.id
}
