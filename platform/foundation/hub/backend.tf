terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stattfstate01"
    container_name       = "tfstate"
    key                  = "platform/foundation/hub.tfstate" # one key per root (ADR-0007)
    use_azuread_auth     = true
  }
}
