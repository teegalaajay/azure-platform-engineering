location                = "eastus2"
environment             = "prod"
data_classification     = "gxp-regulated"
address_space           = ["10.11.0.0/16"]
app_subnet_prefix       = "10.11.1.0/24"
data_subnet_prefix      = "10.11.2.0/24"
hub_vnet_name           = "vnet-hub-shared"
hub_resource_group_name = "rg-network-shared"
# operator_ip_cidr: NOT here. Supplied by TF_VAR_operator_ip_cidr.
