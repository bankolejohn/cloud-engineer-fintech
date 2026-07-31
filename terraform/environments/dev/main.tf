# ==============================================================================
# FinFlow Platform - Development Environment
# Deploys infrastructure across GCP (primary) and AWS (secondary)
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"

  # Remote state in GCS (configure backend per environment)
  backend "gcs" {
    bucket = "finflow-terraform-state"
    prefix = "environments/dev"
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
  }
}

# ==============================================================================
# Provider Configuration
# ==============================================================================

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "dev"
      Project     = "finflow"
      ManagedBy   = "terraform"
    }
  }
}

# ==============================================================================
# Variables
# ==============================================================================

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# ==============================================================================
# GCP Infrastructure
# ==============================================================================

module "gcp_vpc" {
  source = "../../modules/gcp/vpc"

  project_id  = var.gcp_project_id
  region      = var.gcp_region
  environment = "dev"
  vpc_cidr    = "10.0.0.0/16"
  pods_cidr   = "10.1.0.0/16"
  services_cidr = "10.2.0.0/20"
}

module "gcp_gke" {
  source = "../../modules/gcp/gke"

  project_id          = var.gcp_project_id
  region              = var.gcp_region
  environment         = "dev"
  vpc_id              = module.gcp_vpc.vpc_id
  subnet_id           = module.gcp_vpc.gke_subnet_id
  pods_range_name     = module.gcp_vpc.pods_secondary_range_name
  services_range_name = module.gcp_vpc.services_secondary_range_name

  # Dev sizing (cost-conscious)
  machine_type   = "e2-standard-2"
  node_count     = 1
  min_node_count = 1
  max_node_count = 3
  disk_size_gb   = 50
}

module "gcp_cloud_sql" {
  source = "../../modules/gcp/cloud-sql"

  project_id        = var.gcp_project_id
  region            = var.gcp_region
  environment       = "dev"
  vpc_id            = module.gcp_vpc.vpc_id
  tier              = "db-f1-micro" # Small for dev
  disk_size         = 20
  high_availability = false # No HA needed for dev
}

# ==============================================================================
# AWS Infrastructure
# ==============================================================================

module "aws_vpc" {
  source = "../../modules/aws/vpc"

  region      = var.aws_region
  environment = "dev"
  vpc_cidr    = "10.10.0.0/16"
}

module "aws_eks" {
  source = "../../modules/aws/eks"

  region             = var.aws_region
  environment        = "dev"
  vpc_id             = module.aws_vpc.vpc_id
  private_subnet_ids = module.aws_vpc.private_subnet_ids

  # Dev sizing
  node_instance_types = ["t3.medium"]
  node_desired_size   = 1
  node_min_size       = 1
  node_max_size       = 3
}

# ==============================================================================
# Outputs
# ==============================================================================

output "gcp_gke_cluster_name" {
  value = module.gcp_gke.cluster_name
}

output "gcp_gke_endpoint" {
  value     = module.gcp_gke.cluster_endpoint
  sensitive = true
}

output "gcp_mysql_ip" {
  value = module.gcp_cloud_sql.private_ip
}

output "aws_eks_cluster_name" {
  value = module.aws_eks.cluster_name
}

output "aws_eks_endpoint" {
  value = module.aws_eks.cluster_endpoint
}
