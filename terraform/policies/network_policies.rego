# ==============================================================================
# OPA Policy: Network Security Compliance
# Enforces networking security standards across all clouds
# ==============================================================================

package finflow.network

import future.keywords.in

# Deny VPCs/VNets without flow logs
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_vpc"
    flow_logs := [r | r := input.resource_changes[_]; r.type == "aws_flow_log"; r.change.after.vpc_id == resource.change.after.id]
    count(flow_logs) == 0
    msg := sprintf("AWS VPC '%s' must have flow logs enabled", [resource.name])
}

# Deny security groups with 0.0.0.0/0 on SSH
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_security_group"
    ingress := resource.change.after.ingress[_]
    ingress.from_port <= 22
    ingress.to_port >= 22
    cidr := ingress.cidr_blocks[_]
    cidr == "0.0.0.0/0"
    msg := sprintf("Security group '%s' allows SSH from 0.0.0.0/0 - restrict source", [resource.name])
}

# Deny security groups with 0.0.0.0/0 on RDP
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_security_group"
    ingress := resource.change.after.ingress[_]
    ingress.from_port <= 3389
    ingress.to_port >= 3389
    cidr := ingress.cidr_blocks[_]
    cidr == "0.0.0.0/0"
    msg := sprintf("Security group '%s' allows RDP from 0.0.0.0/0", [resource.name])
}

# Deny database subnets with public IP
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_subnet"
    resource.change.after.map_public_ip_on_launch == true
    contains(resource.name, "database")
    msg := sprintf("Database subnet '%s' must not assign public IPs", [resource.name])
}

# Deny RDS instances without encryption
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_db_instance"
    resource.change.after.storage_encrypted != true
    msg := sprintf("RDS instance '%s' must have storage encryption enabled", [resource.name])
}

# Deny RDS with public access
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_db_instance"
    resource.change.after.publicly_accessible == true
    msg := sprintf("RDS instance '%s' must not be publicly accessible", [resource.name])
}

# Deny GCP firewall rules allowing all traffic from 0.0.0.0/0
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_compute_firewall"
    source := resource.change.after.source_ranges[_]
    source == "0.0.0.0/0"
    allow := resource.change.after.allow[_]
    allow.protocol == "all"
    msg := sprintf("Firewall rule '%s' allows all protocols from 0.0.0.0/0", [resource.name])
}

# Require encryption on Cloud SQL
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_sql_database_instance"
    not resource.change.after.settings[_].ip_configuration[_].ipv4_enabled == false
    msg := sprintf("Cloud SQL '%s' should disable public IP (use private IP only)", [resource.name])
}
