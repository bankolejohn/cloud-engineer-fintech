# ==============================================================================
# Azure AKS Module
# Production AKS cluster with Azure CNI, autoscaling, and Azure AD integration
# ==============================================================================

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vnet_subnet_id" {
  description = "Subnet ID for AKS nodes"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "node_count" {
  description = "Default node count"
  type        = number
  default     = 2
}

variable "min_count" {
  description = "Minimum node count for autoscaler"
  type        = number
  default     = 1
}

variable "max_count" {
  description = "Maximum node count for autoscaler"
  type        = number
  default     = 5
}

variable "vm_size" {
  description = "VM size for nodes"
  type        = string
  default     = "Standard_D4s_v3"
}

locals {
  cluster_name = "finflow-${var.environment}-aks"
  common_tags = {
    Environment = var.environment
    Project     = "finflow"
    ManagedBy   = "terraform"
  }
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = local.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "finflow-${var.environment}"
  kubernetes_version  = var.kubernetes_version

  # System node pool
  default_node_pool {
    name                = "system"
    node_count          = var.node_count
    vm_size             = var.vm_size
    vnet_subnet_id      = var.vnet_subnet_id
    enable_auto_scaling = true
    min_count           = var.min_count
    max_count           = var.max_count
    os_disk_size_gb     = 100
    os_disk_type        = "Managed"
    max_pods            = 50

    node_labels = {
      "nodepool" = "system"
    }
  }

  # Identity
  identity {
    type = "SystemAssigned"
  }

  # Network profile (Azure CNI for better pod networking)
  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    load_balancer_sku = "standard"
    outbound_type     = "userAssignedNATGateway"
  }

  # Azure Monitor
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id
  }

  # Key Vault secrets provider
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "5m"
  }

  # Auto-upgrade channel
  automatic_channel_upgrade = "stable"

  # Maintenance window
  maintenance_window {
    allowed {
      day   = "Sunday"
      hours = [2, 3, 4]
    }
  }

  tags = local.common_tags
}

# User node pool (application workloads)
resource "azurerm_kubernetes_cluster_node_pool" "application" {
  name                  = "apppool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = "Standard_D4s_v3"
  node_count            = 1
  enable_auto_scaling   = true
  min_count             = 1
  max_count             = 5
  vnet_subnet_id        = var.vnet_subnet_id
  os_disk_size_gb       = 100
  max_pods              = 50

  node_labels = {
    "nodepool" = "application"
  }

  tags = local.common_tags
}

# Spot node pool (cost optimization)
resource "azurerm_kubernetes_cluster_node_pool" "spot" {
  name                  = "spot"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = "Standard_D4s_v3"
  node_count            = 0
  enable_auto_scaling   = true
  min_count             = 0
  max_count             = 3
  priority              = "Spot"
  eviction_policy       = "Delete"
  spot_max_price        = -1 # Pay up to on-demand price
  vnet_subnet_id        = var.vnet_subnet_id

  node_labels = {
    "nodepool"                          = "spot"
    "kubernetes.azure.com/scalesetpriority" = "spot"
  }

  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
  ]

  tags = local.common_tags
}

# Log Analytics Workspace for AKS monitoring
resource "azurerm_log_analytics_workspace" "aks" {
  name                = "${local.cluster_name}-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

# Outputs
output "cluster_id" {
  value = azurerm_kubernetes_cluster.main.id
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive = true
}

output "cluster_fqdn" {
  value = azurerm_kubernetes_cluster.main.fqdn
}

output "kubelet_identity" {
  value = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
