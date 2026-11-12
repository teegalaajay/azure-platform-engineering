location            = "eastus2"
environment         = "shared"
data_classification = "internal"

private_dns_zones = {
  blob  = "privatelink.blob.core.windows.net"
  vault = "privatelink.vaultcore.azure.net"
  acr   = "privatelink.azurecr.io"
}

linked_vnets = {
  hub  = { name = "vnet-hub-shared", resource_group_name = "rg-network-shared" }
  dev  = { name = "vnet-spoke-dev", resource_group_name = "rg-network-dev" }
  prod = { name = "vnet-spoke-prod", resource_group_name = "rg-network-prod" }
}
