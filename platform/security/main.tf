locals {
  common_tags = {
    owner       = "platform-team"
    cost_center = "cc-platform-001"
    managed_by  = "terraform"
    repo        = "azure-platform-engineering"
  }

  tags = merge(local.common_tags, {
    environment         = "shared" # one instance serves all environments
    data_classification = var.data_classification
  })
}

# Tenant ID and the caller's object ID, read from the identity running Terraform.
data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = "rg-security-shared"
  location = var.location
  tags     = local.tags
}

resource "azurerm_key_vault" "this" {
  name                = var.key_vault_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard" # ADR-0010 B3: secrets only, no HSM keys

  # ADR-0010 B4/B5: hardcoded, never variables (open item 26).
  rbac_authorization_enabled = true # data-plane access via role assignments only
  purge_protection_enabled   = true # irreversible
  soft_delete_retention_days = 90   # fixed at creation

  # No Azure service may pull secrets through ARM on our behalf.
  enabled_for_deployment          = false
  enabled_for_disk_encryption     = false
  enabled_for_template_deployment = false

  public_network_access_enabled = true # endpoint stays on; network_acls restricts it (private endpoint W8)

  network_acls {
    default_action = "Deny"
    bypass         = "None"                                # ADR-0010 B7
    ip_rules       = [split("/", var.operator_ip_cidr)[0]] # bare IP, same form as storage-demo
    virtual_network_subnet_ids = [
      data.terraform_remote_state.hub.outputs.mgmt_subnet_id, # hub snet-mgmt (KeyVault SE)
    ]
  }
  lifecycle {
    prevent_destroy = true # ADR-0010: plan-time guard; deletion would reserve the name for 90 days
  }
  tags = local.tags
}

# Allowed paths are read from their owners, never typed (ADR-0009 pattern).
data "terraform_remote_state" "hub" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stattfstate01"
    container_name       = "tfstate"
    key                  = "platform/foundation/hub.tfstate"
    use_azuread_auth     = true
  }
}


# ADR-0010 B6: least privilege, vault scope, explicit principal (never client_config).
resource "azurerm_role_assignment" "operator_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer" # name checked by ARM at apply, not by plan
  principal_id         = var.operator_object_id
  principal_type       = "User" # lets ARM skip the directory lookup that fails on brand-new principals
  description          = "Operator manages platform secrets (ADR-0010)"
}

# ADR-0010: ARM-side guard against deletes from any client (portal, CLI, other roots).
resource "azurerm_management_lock" "kv_cannot_delete" {
  name       = "lock-cannotdelete-${azurerm_key_vault.this.name}"
  scope      = azurerm_key_vault.this.id
  lock_level = "CanNotDelete"
  notes      = "Platform Key Vault: remove only via reviewed PR (ADR-0010)"

  lifecycle {
    prevent_destroy = true # removing the lock must be a deliberate two-step change
  }
}
