# Copy into every root module under platform/ and workloads/. Change only `key`.
# Convention: key = "<folder>/<module>.tfstate"  e.g. "platform/foundation.tfstate"
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stattfstate01" # from engineering_standards.md §3
    container_name       = "tfstate"
    key                  = "platform/cost.tfstate"
    use_azuread_auth     = true # Entra ID, no storage keys
  }
}
