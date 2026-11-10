# Subscription comes from ARM_SUBSCRIPTION_ID (never committed). Control plane only: no Kubernetes or
# Helm provider here. Objects inside the cluster are applied with kubectl (runbook platform-aks).
provider "azurerm" {
  features {}
}
