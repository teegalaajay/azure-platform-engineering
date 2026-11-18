location            = "eastus2"
vault_name          = "rsv-plat-shared-at01"
data_classification = "gxp-regulated" # the vault holds recovery points of regulated workloads
storage_mode_type   = "GeoRedundant"  # ADR-0045 decision 2: Cross Region Restore needs GRS; fixed once protection starts
immutability        = "Unlocked"      # ADR-0045 decision 3: Locked is irreversible and refused in variables.tf
