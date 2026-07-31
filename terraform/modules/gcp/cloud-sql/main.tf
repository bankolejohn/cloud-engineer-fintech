# ==============================================================================
# GCP Cloud SQL Module
# MySQL instance with HA, private networking, and automated backups
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
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC network ID for private IP"
  type        = string
}

variable "tier" {
  description = "Cloud SQL machine type"
  type        = string
  default     = "db-n1-standard-2"
}

variable "disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 50
}

variable "high_availability" {
  description = "Enable HA (regional) for the instance"
  type        = bool
  default     = true
}

variable "database_name" {
  description = "Default database name"
  type        = string
  default     = "finflow"
}

# Cloud SQL MySQL Instance
resource "google_sql_database_instance" "primary" {
  name                = "finflow-${var.environment}-mysql"
  project             = var.project_id
  region              = var.region
  database_version    = "MYSQL_8_0"
  deletion_protection = var.environment == "prod" ? true : false

  settings {
    tier              = var.tier
    disk_size         = var.disk_size
    disk_type         = "PD_SSD"
    disk_autoresize   = true
    availability_type = var.high_availability ? "REGIONAL" : "ZONAL"

    # Network: Private IP only (no public access)
    ip_configuration {
      ipv4_enabled    = false
      private_network = var.vpc_id

      # No authorized networks since private IP only
    }

    # Backup configuration
    backup_configuration {
      enabled                        = true
      binary_log_enabled             = true
      start_time                     = "03:00" # 3 AM UTC
      location                       = var.region
      point_in_time_recovery_enabled = true

      backup_retention_settings {
        retained_backups = 30
        retention_unit   = "COUNT"
      }
    }

    # Maintenance window
    maintenance_window {
      day          = 7 # Sunday
      hour         = 4 # 4 AM UTC
      update_track = "stable"
    }

    # Database flags for performance
    database_flags {
      name  = "slow_query_log"
      value = "on"
    }

    database_flags {
      name  = "long_query_time"
      value = "1"
    }

    database_flags {
      name  = "max_connections"
      value = "500"
    }

    database_flags {
      name  = "innodb_buffer_pool_size"
      value = "1073741824" # 1GB
    }

    # Insights (query performance)
    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = 5
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    user_labels = {
      environment = var.environment
      team        = "platform"
      managed_by  = "terraform"
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

# Read replica (for ProxySQL read/write splitting)
resource "google_sql_database_instance" "replica" {
  count = var.environment == "prod" ? 1 : 0

  name                 = "finflow-${var.environment}-mysql-replica"
  project              = var.project_id
  region               = var.region
  database_version     = "MYSQL_8_0"
  master_instance_name = google_sql_database_instance.primary.name
  deletion_protection  = false

  replica_configuration {
    failover_target = false
  }

  settings {
    tier            = var.tier
    disk_size       = var.disk_size
    disk_type       = "PD_SSD"
    disk_autoresize = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.vpc_id
    }

    database_flags {
      name  = "max_connections"
      value = "500"
    }
  }
}

# Database
resource "google_sql_database" "finflow" {
  name     = var.database_name
  project  = var.project_id
  instance = google_sql_database_instance.primary.name
  charset  = "utf8mb4"
}

# Application user (password managed by Vault in production)
resource "google_sql_user" "app_user" {
  name     = "finflow_app"
  project  = var.project_id
  instance = google_sql_database_instance.primary.name
  password = "CHANGE_ME_USE_VAULT" # Rotated by Vault dynamic secrets
}

# Outputs
output "instance_name" {
  value = google_sql_database_instance.primary.name
}

output "instance_connection_name" {
  value = google_sql_database_instance.primary.connection_name
}

output "private_ip" {
  value = google_sql_database_instance.primary.private_ip_address
}

output "replica_private_ip" {
  value = var.environment == "prod" ? google_sql_database_instance.replica[0].private_ip_address : ""
}

output "database_name" {
  value = google_sql_database.finflow.name
}
