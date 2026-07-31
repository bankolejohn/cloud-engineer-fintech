# ==============================================================================
# OCI OKE Module
# Oracle Kubernetes Engine cluster for batch processing workloads
# ==============================================================================

variable "compartment_id" {
  description = "OCI compartment OCID"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vcn_id" {
  description = "VCN OCID"
  type        = string
}

variable "nodes_subnet_id" {
  description = "Subnet OCID for worker nodes"
  type        = string
}

variable "pods_subnet_id" {
  description = "Subnet OCID for pods (VCN-native pod networking)"
  type        = string
}

variable "lb_subnet_id" {
  description = "Subnet OCID for load balancers"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "v1.28.2"
}

variable "node_shape" {
  description = "Compute shape for nodes"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "node_ocpus" {
  description = "Number of OCPUs per node"
  type        = number
  default     = 2
}

variable "node_memory_gb" {
  description = "Memory in GB per node"
  type        = number
  default     = 16
}

variable "node_count" {
  description = "Number of nodes in the pool"
  type        = number
  default     = 2
}

locals {
  cluster_name = "finflow-${var.environment}-oke"
}

# OKE Cluster
resource "oci_containerengine_cluster" "main" {
  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version
  name               = local.cluster_name
  vcn_id             = var.vcn_id

  cluster_pod_network_options {
    cni_type = "OCI_VCN_IP_NATIVE"
  }

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = var.lb_subnet_id
  }

  options {
    service_lb_subnet_ids = [var.lb_subnet_id]

    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }

    admission_controller_options {
      is_pod_security_policy_enabled = false
    }
  }

  freeform_tags = {
    Environment = var.environment
    Project     = "finflow"
    ManagedBy   = "terraform"
  }
}

# Node Pool
resource "oci_containerengine_node_pool" "primary" {
  cluster_id         = oci_containerengine_cluster.main.id
  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version
  name               = "${local.cluster_name}-primary-pool"

  node_shape = var.node_shape

  node_shape_config {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_gb
  }

  node_config_details {
    size = var.node_count

    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id           = var.nodes_subnet_id
    }

    node_pool_pod_network_option_details {
      cni_type          = "OCI_VCN_IP_NATIVE"
      pod_subnet_ids    = [var.pods_subnet_id]
      max_pods_per_node = 31
    }
  }

  node_source_details {
    image_id    = data.oci_containerengine_node_pool_option.main.sources[0].image_id
    source_type = "IMAGE"
  }

  initial_node_labels {
    key   = "environment"
    value = var.environment
  }

  initial_node_labels {
    key   = "pool"
    value = "primary"
  }

  freeform_tags = {
    Environment = var.environment
    Project     = "finflow"
    ManagedBy   = "terraform"
  }
}

# Data sources
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

data "oci_containerengine_node_pool_option" "main" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_id
}

# Outputs
output "cluster_id" {
  value = oci_containerengine_cluster.main.id
}

output "cluster_name" {
  value = oci_containerengine_cluster.main.name
}

output "cluster_kubernetes_version" {
  value = oci_containerengine_cluster.main.kubernetes_version
}

output "node_pool_id" {
  value = oci_containerengine_node_pool.primary.id
}
