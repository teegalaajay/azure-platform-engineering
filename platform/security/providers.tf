provider "azurerm" {
  features {
    key_vault {
      # Destroy soft-deletes only; never purge. Purge protection would refuse anyway,
      # and the vault holds secrets we may need back.
      purge_soft_delete_on_destroy          = false
      purge_soft_deleted_secrets_on_destroy = false
      # If a soft-deleted vault/secret with the same name exists, recover it
      # instead of failing the create.
      recover_soft_deleted_key_vaults = true
      recover_soft_deleted_secrets    = true
    }
  }
  storage_use_azuread = true
}
