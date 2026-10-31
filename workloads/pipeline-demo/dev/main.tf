locals {
  common_tags = {
    owner       = "platform-team"
    cost_center = "cc-platform-001"
    managed_by  = "terraform"
    repo        = "azure-platform-engineering"
  }

  # Environment-specific tags go last so they win on any duplicate key.
  tags = merge(local.common_tags, {
    environment         = var.environment
    data_classification = var.data_classification
  })
}

resource "azurerm_resource_group" "this" {
  name     = "rg-pipeline-demo-${var.environment}"
  location = var.location
  tags     = local.tags
}
