locals {
  common_tags = {
    owner       = "platform-team"
    cost_center = "cc-platform-001"
    managed_by  = "terraform"
    repo        = "azure-platform-engineering"
  }

  tags = merge(local.common_tags, {
    environment         = "shared" # one workspace serves all environments
    data_classification = var.data_classification
  })
}

resource "azurerm_resource_group" "this" {
  name     = "rg-management-shared"
  location = var.location
  tags     = local.tags
}

# Central Log Analytics workspace (ADR-0044). Sources push into it through diagnostic settings.
resource "azurerm_log_analytics_workspace" "this" {
  name                = var.workspace_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  sku               = "PerGB2018" # pay per GB ingested; no commitment tier
  retention_in_days = var.retention_in_days
  daily_quota_gb    = var.daily_quota_gb

  # Entra identities only: the two shared keys are disabled (ADR-0044).
  local_authentication_enabled = false

  # Public endpoints stay on until Private Link exists (accepted risk, ADR-0044).
  internet_ingestion_enabled = true
  internet_query_enabled     = true

  lifecycle {
    prevent_destroy = true # plan-time guard: audit data is not removed by a stray destroy
  }

  tags = local.tags
}

# ARM-side guard against deletes from any client (portal, CLI, other roots).
resource "azurerm_management_lock" "workspace_cannot_delete" {
  name       = "lock-cannotdelete-${azurerm_log_analytics_workspace.this.name}"
  scope      = azurerm_log_analytics_workspace.this.id
  lock_level = "CanNotDelete"
  notes      = "Platform Log Analytics workspace: remove only via reviewed PR (ADR-0044)"

  lifecycle {
    prevent_destroy = true # removing the lock must be a deliberate two-step change
  }
}
