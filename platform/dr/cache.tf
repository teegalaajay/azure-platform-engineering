# The source subnet is read, never managed, by this root (ADR-0007: one root per network).
data "azurerm_subnet" "source_app" {
  name                 = "snet-app"
  virtual_network_name = var.source_vnet_name
  resource_group_name  = var.source_resource_group_name
}

# ASR cache (staging) account (ADR-0045). The Mobility service on the source VM writes changes here
# before they are copied to the replica disks. Shared key stays off (platform-baseline Deny rule);
# the vault reaches the account with its own identity.
resource "azurerm_storage_account" "cache" {
  name                = var.cache_account_name
  resource_group_name = azurerm_resource_group.this.name
  location            = var.cache_location

  account_tier             = "Standard"
  account_kind             = "StorageV2"
  account_replication_type = "ZRS"

  shared_access_key_enabled       = false
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [data.azurerm_subnet.source_app.id]
  }

  lifecycle {
    prevent_destroy = true # ASR depends on this account while any VM replicates
  }

  tags = local.tags
}

# Read-write access for the vault identity on this account only (ADR-0045). The role is the one a
# secondary source names; the first replication in Part F proves or disproves it.
resource "azurerm_role_assignment" "vault_cache_blob_contributor" {
  scope                = azurerm_storage_account.cache.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_recovery_services_vault.this.identity[0].principal_id
}

# Enabling replication failed with error 28143 (vault has no permission on the cache account)
# while the vault identity held only the blob data role above (ADR-0045).
resource "azurerm_role_assignment" "vault_cache_contributor" {
  scope                = azurerm_storage_account.cache.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_recovery_services_vault.this.identity[0].principal_id
}
