# ==============================================================================
# OPA Policy: General Infrastructure Compliance
# Enforces tagging, naming conventions, and cost guardrails
# ==============================================================================

package finflow.general

import future.keywords.in

# Required tags for all resources
required_tags := {"Environment", "Project", "ManagedBy"}

# Deny AWS resources without required tags
deny[msg] {
    resource := input.resource_changes[_]
    startswith(resource.type, "aws_")
    resource.change.after.tags != null
    tags := resource.change.after.tags
    required := required_tags[_]
    not tags[required]
    msg := sprintf("AWS resource '%s' (%s) is missing required tag: %s", [resource.name, resource.type, required])
}

# Deny GCP resources without required labels
deny[msg] {
    resource := input.resource_changes[_]
    startswith(resource.type, "google_")
    some key in ["environment", "project", "managed_by"]
    labels := resource.change.after.labels
    labels != null
    not labels[key]
    msg := sprintf("GCP resource '%s' (%s) is missing required label: %s", [resource.name, resource.type, key])
}

# Cost guardrail: Deny oversized instances in dev
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_instance"
    contains(resource.name, "dev")
    instance_type := resource.change.after.instance_type
    expensive_types := {"m5.2xlarge", "m5.4xlarge", "c5.4xlarge", "r5.2xlarge"}
    instance_type in expensive_types
    msg := sprintf("Instance '%s' uses expensive type '%s' in dev environment", [resource.name, instance_type])
}

# Cost guardrail: Deny large GKE node pools in dev
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_container_node_pool"
    contains(resource.name, "dev")
    autoscaling := resource.change.after.autoscaling[_]
    autoscaling.max_node_count > 5
    msg := sprintf("Node pool '%s' max_node_count exceeds 5 in dev environment", [resource.name])
}

# Naming convention enforcement
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "google_container_cluster"
    not startswith(resource.change.after.name, "finflow-")
    msg := sprintf("GKE cluster '%s' must follow naming convention: finflow-<env>-<purpose>", [resource.name])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_eks_cluster"
    not startswith(resource.change.after.name, "finflow-")
    msg := sprintf("EKS cluster '%s' must follow naming convention: finflow-<env>-<purpose>", [resource.name])
}
