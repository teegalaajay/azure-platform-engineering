# Key Vault diagnostic settings enforced by policy (ADR-0044). The workspace ID comes from
# platform/management, which must be applied first.
data "terraform_remote_state" "management" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stattfstate01"
    container_name       = "tfstate"
    key                  = "platform/management.tfstate"
    use_azuread_auth     = true
  }
}

# Built-in definition bef3f64c (v3.0.0 when read). The system-assigned identity runs the
# deployment that creates the diagnostic setting. Policy and role assignments support no tags
# (same exception as the management group, ADR-0040).
resource "azurerm_management_group_policy_assignment" "diagnostics_keyvault" {
  name                 = "diag-keyvault-to-law"
  display_name         = "Key Vault diagnostic settings to the platform workspace"
  management_group_id  = azurerm_management_group.platform.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/bef3f64c-5290-43b7-85b0-9b254eef4c47"
  location             = "eastus2"

  identity {
    type = "SystemAssigned"
  }

  non_compliance_message {
    content = "This Key Vault has no diagnostic setting sending AuditEvent to the platform workspace."
  }

  # The two enable switches are strings in the definition; matchWorkspace is a boolean.
  parameters = jsonencode({
    effect         = { value = "DeployIfNotExists" }
    logAnalytics   = { value = data.terraform_remote_state.management.outputs.workspace_id }
    logsEnabled    = { value = "True" }
    metricsEnabled = { value = "False" }
    matchWorkspace = { value = true }
  })
}

# Writes the setting onto each vault: wide scope on purpose, so later subscriptions are covered.
resource "azurerm_role_assignment" "diagnostics_monitoring" {
  scope                = azurerm_management_group.platform.id
  role_definition_name = "Monitoring Contributor"
  principal_id         = azurerm_management_group_policy_assignment.diagnostics_keyvault.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# Links the setting to the workspace: one resource, one assignment.
resource "azurerm_role_assignment" "diagnostics_workspace" {
  scope                = data.terraform_remote_state.management.outputs.workspace_id
  role_definition_name = "Log Analytics Contributor"
  principal_id         = azurerm_management_group_policy_assignment.diagnostics_keyvault.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
