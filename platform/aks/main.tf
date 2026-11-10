locals {
  common_tags = {
    owner       = "platform-team"
    cost_center = "cc-platform-001"
    managed_by  = "terraform"
    repo        = "azure-platform-engineering"
  }

  tags = merge(local.common_tags, {
    environment         = var.environment
    data_classification = var.data_classification
  })
}

# Read, never managed here: the spoke network root (ADR-0007) and the registry root (ADR-0036) own these.
data "azurerm_subnet" "nodes" {
  name                 = "snet-aks-nodes"
  virtual_network_name = var.vnet_name
  resource_group_name  = var.network_resource_group_name
}

data "azurerm_network_security_group" "nodes" {
  name                = "nsg-aks-nodes-${trimprefix(var.vnet_name, "vnet-")}"
  resource_group_name = var.network_resource_group_name
}

data "azurerm_container_registry" "this" {
  name                = var.registry_name
  resource_group_name = var.registry_resource_group_name
}

resource "azurerm_resource_group" "this" {
  name     = "rg-aks-${var.environment}"
  location = var.location
  tags     = local.tags
}

# User-assigned, so the identity and its subnet role exist before the cluster is created.
resource "azurerm_user_assigned_identity" "cluster" {
  name                = "id-aks-${var.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

# Control plane joins node NICs to the subnet. Scope: this one subnet only (ADR-0038).
resource "azurerm_role_assignment" "subnet_join" {
  scope                            = data.azurerm_subnet.nodes.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_user_assigned_identity.cluster.principal_id
  skip_service_principal_aad_check = true # new identity: skip the Entra lookup that can lag behind creation
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-platform-${var.environment}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = "aks-platform-${var.environment}"
  node_resource_group = "rg-aks-nodes-${var.environment}" # named, so destroy can be checked by name

  sku_tier                  = "Free" # no financially backed SLA; acceptable for a reference platform
  oidc_issuer_enabled       = true   # workload identity needs the issuer
  workload_identity_enabled = true
  local_account_disabled    = false # static admin credential exists; accepted risk, exit = Entra RBAC (ADR-0038)

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  default_node_pool {
    name = "system"
    # The azurerm ruleset v0.32.0 size list predates the v7 sizes; Azure accepted this size (ADR-0038).
    # tflint-ignore: azurerm_kubernetes_cluster_default_node_pool_invalid_vm_size
    vm_size                      = var.system_vm_size
    node_count                   = 2
    vnet_subnet_id               = data.azurerm_subnet.nodes.id
    only_critical_addons_enabled = true # taint CriticalAddonsOnly: workloads go to the user pool
    temporary_name_for_rotation  = "systemtmp"
    upgrade_settings {
      max_surge                     = "10%" # the AKS default, read back after creation (ADR-0038)
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }

  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = var.pod_cidr
    service_cidr        = "10.0.0.0/16" # virtual, never routed: must not overlap 10.10/16, 10.11/16, 10.20/16
    dns_service_ip      = "10.0.0.10"
    outbound_type       = "loadBalancer"
    load_balancer_sku   = "standard"
  }

  tags = local.tags

  depends_on = [azurerm_role_assignment.subnet_join]

  lifecycle {
    # pod_cidr is set here and as aks_pod_cidr in platform/foundation/<env>. Fail the plan, not the traffic.
    precondition {
      condition = anytrue([
        for r in data.azurerm_network_security_group.nodes.security_rule :
        r.direction == "Inbound" && r.access == "Allow" && r.source_address_prefix == var.pod_cidr
      ])
      error_message = "No inbound Allow rule on the node subnet NSG has source ${var.pod_cidr}. Set pod_cidr and aks_pod_cidr in platform/foundation/${var.environment} to the same range."
    }
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  mode                  = "User"
  # The azurerm ruleset v0.32.0 size list predates the v7 sizes; Azure accepted this size (ADR-0038).
  # tflint-ignore: azurerm_kubernetes_cluster_node_pool_invalid_vm_size
  vm_size        = var.user_vm_size
  node_count     = 1
  vnet_subnet_id = data.azurerm_subnet.nodes.id
  tags           = local.tags
  upgrade_settings {
    max_surge                     = "10%"
    drain_timeout_in_minutes      = 0
    node_soak_duration_in_minutes = 0
  }
}

# The first apply of Part D sets grant_acr_pull=false to observe the refusal; the committed value is true.
resource "azurerm_role_assignment" "acr_pull" {
  count = var.grant_acr_pull ? 1 : 0

  scope                            = data.azurerm_container_registry.this.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}
