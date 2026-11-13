location            = "eastus2"
workspace_name      = "log-plat-shared-at01"
data_classification = "confidential" # audit logs of platform resources; same class as the vault
daily_quota_gb      = 0.2            # ADR-0044 decision 1
retention_in_days   = 90             # ADR-0044 decision 2
