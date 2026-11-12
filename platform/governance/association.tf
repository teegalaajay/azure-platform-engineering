# Moves the subscription under mg-platform. Until this exists the group is empty and the
# assignment evaluates nothing. Removing this resource moves the subscription back to the
# Tenant Root Group (ADR-0040).
data "azurerm_subscription" "current" {}

resource "azurerm_management_group_subscription_association" "platform" {
  management_group_id = azurerm_management_group.platform.id
  subscription_id     = data.azurerm_subscription.current.id
}
