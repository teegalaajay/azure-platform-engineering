locals {
  common_tags = {
    owner       = "platform-team"
    cost_center = "cc-platform-001"
    managed_by  = "terraform"
    repo        = "azure-platform-engineering"
  }

  tags = merge(local.common_tags, {
    environment         = "shared" # one identity serves the shared agent
    data_classification = var.data_classification
  })
}

# The vault is owned by the security root; read its ID from that state, never type it.
data "terraform_remote_state" "security" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stattfstate01"
    container_name       = "tfstate"
    key                  = "platform/security.tfstate"
    use_azuread_auth     = true
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-agent-identity-shared"
  location = var.location
  tags     = local.tags
}

# ADR-0024: user-assigned, so the identity and its role exist before the VM and survive a rebuild.
resource "azurerm_user_assigned_identity" "agent" {
  name                = "id-ado-agent-shared"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

# Least privilege: read secret values on this one vault, nothing else (ADR-0024).
resource "azurerm_role_assignment" "agent_secrets_user" {
  scope                = data.terraform_remote_state.security.outputs.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
  principal_type       = "ServicePrincipal" # lets ARM skip the directory lookup that fails on brand-new principals
  description          = "ADO agent VM reads the agent token and pipeline secrets (ADR-0024)"
}
