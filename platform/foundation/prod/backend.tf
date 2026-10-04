terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stattfstate01"
    container_name       = "tfstate"
    key                  = "platform/foundation/prod.tfstate"
    use_azuread_auth     = true
  }
}
