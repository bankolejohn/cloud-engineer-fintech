# ==============================================================================
# FinFlow Platform - Production Environment
# Full multi-cloud deployment: GCP + AWS + Azure + OCI
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"

  backend "gcs" {
    bucket = "finflow-terraform-state"
    prefix = "environments/prod"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.10"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
    oci = {
      source  = "oracle/oci"
      version = "~> 5.25"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "aws" {
  region = var.aws_region
}

provider "azurerm" {
  features {}
}

provider "oci" {
  region = var.oci_region
}

# ==============================================================================
# Variables
# ==============================================================================

variable "gcp_project_id" {
  type = string
}

variable "gcp_region" {
  type    = string
  default = "us-central1"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "azure_location" {
  type    = string
  default = "eastus"
}

variable "oci_region" {
  type    = string
  default = "us-ashburn-1"
}

variable "oci_compartment_id" {
  type = string
}

variable "vpn_shared_secret" {
  type      = string
  sensitive = true
}

# ==============================================================================
# GCP (Primary Cloud)
# ==============================================================================

module "gcp_vpc" {
  source = "../../modules/gcp/vpc"

  project_id  = var.gcp_project_id
  region      = var.gcp_region
  environment = "prod"
}

module "gcp_gke" {
  source = "../../modules/gcp/gke"

  project_id          = var.gcp_project_id
  region              = var.gcp_region
  environment         = "prod"
  vpc_id              = module.gcp_vpc.vpc_id
  subnet_id           = module.gcp_vpc.gke_subnet_id
  pods_range_name     = module.gcp_vpc.pods_secondary_range_name
  services_range_name = module.gcp_vpc.services_secondary_range_name

  # Production sizing
  machine_type   = "e2-standard-4"
  node_count     = 3
  min_node_count = 3
  max_node_count = 10
  disk_size_gb   = 100
}

module "gcp_cloud_sql" {
  source = "../../modules/gcp/cloud-sql"

  project_id        = var.gcp_project_id
  region            = var.gcp_region
  environment       = "prod"
  vpc_id            = module.gcp_vpc.vpc_id
  tier              = "db-n1-standard-4"
  disk_size         = 100
  high_availability = true
}

# ==============================================================================
# AWS (Secondary Cloud)
# ==============================================================================

module "aws_vpc" {
  source = "../../modules/aws/vpc"

  region      = var.aws_region
  environment = "prod"
}

module "aws_eks" {
  source = "../../modules/aws/eks"

  region             = var.aws_region
  environment        = "prod"
  vpc_id             = module.aws_vpc.vpc_id
  private_subnet_ids = module.aws_vpc.private_subnet_ids

  node_instance_types = ["m5.xlarge"]
  node_desired_size   = 3
  node_min_size       = 3
  node_max_size       = 10
}

module "aws_rds" {
  source = "../../modules/aws/rds"

  environment                = "prod"
  vpc_id                     = module.aws_vpc.vpc_id
  database_subnet_group_name = module.aws_vpc.database_subnet_group_name
  instance_class             = "db.r5.large"
  allocated_storage          = 100
  multi_az                   = true
}

# ==============================================================================
# Azure (EU Compliance)
# ==============================================================================

module "azure_vnet" {
  source = "../../modules/azure/vnet"

  resource_group_name = "finflow-prod"
  location            = var.azure_location
  environment         = "prod"
}

module "azure_aks" {
  source = "../../modules/azure/aks"

  resource_group_name = module.azure_vnet.resource_group_name
  location            = var.azure_location
  environment         = "prod"
  vnet_subnet_id      = module.azure_vnet.aks_subnet_id

  vm_size    = "Standard_D4s_v3"
  node_count = 2
  min_count  = 2
  max_count  = 5
}

# ==============================================================================
# OCI (Batch Processing)
# ==============================================================================

module "oci_vcn" {
  source = "../../modules/oci/vcn"

  compartment_id = var.oci_compartment_id
  region         = var.oci_region
  environment    = "prod"
}

module "oci_oke" {
  source = "../../modules/oci/oke"

  compartment_id = var.oci_compartment_id
  environment    = "prod"
  vcn_id         = module.oci_vcn.vcn_id
  nodes_subnet_id = module.oci_vcn.oke_nodes_subnet_id
  pods_subnet_id  = module.oci_vcn.oke_pods_subnet_id
  lb_subnet_id    = module.oci_vcn.public_subnet_id

  node_count = 2
}

# ==============================================================================
# Cross-Cloud VPN (GCP <-> AWS)
# ==============================================================================

module "cross_cloud_vpn" {
  source = "../../modules/networking/cross-cloud-vpn"

  environment     = "prod"
  gcp_project_id  = var.gcp_project_id
  gcp_region      = var.gcp_region
  gcp_vpc_id      = module.gcp_vpc.vpc_id
  gcp_vpc_cidr    = "10.0.0.0/16"
  aws_vpc_id      = module.aws_vpc.vpc_id
  aws_vpc_cidr    = "10.10.0.0/16"
  aws_route_table_ids = [] # Add private route table IDs
  shared_secret   = var.vpn_shared_secret
}

# ==============================================================================
# Outputs
# ==============================================================================

output "gcp_cluster" {
  value = module.gcp_gke.cluster_name
}

output "aws_cluster" {
  value = module.aws_eks.cluster_name
}

output "azure_cluster" {
  value = module.azure_aks.cluster_name
}

output "oci_cluster" {
  value = module.oci_oke.cluster_name
}
