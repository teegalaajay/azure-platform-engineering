# Subscription comes from ARM_SUBSCRIPTION_ID (never committed). Control plane only: no image
# data-plane calls are made from Terraform.
provider "azurerm" {
  features {}
}
