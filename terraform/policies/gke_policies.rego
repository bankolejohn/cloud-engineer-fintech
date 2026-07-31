# ==============================================================================
# OPA Policy: GKE Cluster Compliance
# Enforces security and operational standards for GKE clusters
# ==============================================================================

package finflow.gke

import future.keywords.in

# Deny clusters without Workload Identity
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_container_cluster"
    not resource.change.after.workload_identity_config
    msg := sprintf("GKE cluster '%s' must have Workload Identity enabled", [resource.name])
}

# Deny clusters without network policy
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_container_cluster"
    not resource.change.after.network_policy[_].enabled
    msg := sprintf("GKE cluster '%s' must have network policy enabled for Istio", [resource.name])
}

# Deny clusters with public endpoint in production
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_container_cluster"
    resource.change.after.private_cluster_config[_].enable_private_endpoint == false
    contains(resource.name, "prod")
    msg := sprintf("Production GKE cluster '%s' should use private endpoint only", [resource.name])
}

# Deny node pools without shielded instance
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_container_node_pool"
    config := resource.change.after.node_config[_]
    not config.shielded_instance_config[_].enable_secure_boot
    msg := sprintf("Node pool '%s' must have Shielded VM with Secure Boot enabled", [resource.name])
}

# Deny clusters without binary authorization
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_container_cluster"
    not resource.change.after.binary_authorization
    msg := sprintf("GKE cluster '%s' must have Binary Authorization enabled", [resource.name])
}

# Require logging and monitoring
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_container_cluster"
    not resource.change.after.logging_config
    msg := sprintf("GKE cluster '%s' must have logging configured", [resource.name])
}

# Require maintenance window
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_container_cluster"
    not resource.change.after.maintenance_policy
    msg := sprintf("GKE cluster '%s' must have a maintenance window configured", [resource.name])
}
