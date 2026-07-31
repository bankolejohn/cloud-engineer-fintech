# ==============================================================================
# AWS RDS Module
# MySQL Multi-AZ with read replicas, encryption, and automated backups
# ==============================================================================

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "database_subnet_group_name" {
  description = "DB subnet group name"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "allocated_storage" {
  description = "Storage in GB"
  type        = number
  default     = 50
}

variable "database_name" {
  description = "Database name"
  type        = string
  default     = "finflow"
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = true
}

locals {
  name_prefix = "finflow-${var.environment}"
  common_tags = {
    Environment = var.environment
    Project     = "finflow"
    ManagedBy   = "terraform"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name_prefix = "${local.name_prefix}-rds-sg"
  vpc_id      = var.vpc_id
  description = "Security group for FinFlow RDS"

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.10.0.0/16"] # VPC CIDR
    description = "MySQL from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}

# RDS Parameter Group
resource "aws_db_parameter_group" "mysql" {
  name   = "${local.name_prefix}-mysql-params"
  family = "mysql8.0"

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "1"
  }

  parameter {
    name  = "max_connections"
    value = "500"
  }

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "binlog_format"
    value = "ROW"
  }

  tags = local.common_tags
}

# KMS key for RDS encryption
resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS encryption - ${local.name_prefix}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = local.common_tags
}

# RDS Primary Instance
resource "aws_db_instance" "primary" {
  identifier     = "${local.name_prefix}-mysql"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 2
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.rds.arn

  db_name  = var.database_name
  username = "finflow_admin"
  password = "CHANGE_ME_USE_VAULT" # Rotated by Vault

  multi_az               = var.multi_az
  db_subnet_group_name   = var.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.mysql.name

  # Backup
  backup_retention_period = 30
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Monitoring
  monitoring_interval          = 60
  performance_insights_enabled = true

  # Protection
  deletion_protection = var.environment == "prod"
  skip_final_snapshot = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${local.name_prefix}-final-snapshot" : null

  # Logs
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]

  tags = local.common_tags
}

# Read Replica
resource "aws_db_instance" "replica" {
  count = var.environment == "prod" ? 1 : 0

  identifier          = "${local.name_prefix}-mysql-replica"
  replicate_source_db = aws_db_instance.primary.identifier
  instance_class      = var.instance_class
  storage_encrypted   = true

  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.mysql.name

  monitoring_interval          = 60
  performance_insights_enabled = true
  skip_final_snapshot          = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mysql-replica"
  })
}

# Outputs
output "primary_endpoint" {
  value = aws_db_instance.primary.endpoint
}

output "primary_address" {
  value = aws_db_instance.primary.address
}

output "replica_endpoint" {
  value = var.environment == "prod" ? aws_db_instance.replica[0].endpoint : ""
}

output "database_name" {
  value = aws_db_instance.primary.db_name
}

output "security_group_id" {
  value = aws_security_group.rds.id
}
