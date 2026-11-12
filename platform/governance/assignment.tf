# The assignment is what makes the initiative do anything. Scope: the management group, so it
# reaches every subscription placed under it. No identity: both members only audit or deny.
resource "azurerm_management_group_policy_assignment" "platform_baseline" {
  name                 = "platform-baseline"
  display_name         = "Platform baseline"
  management_group_id  = azurerm_management_group.platform.id
  policy_definition_id = azurerm_management_group_policy_set_definition.platform_baseline.id

  parameters = jsonencode({
    effect           = { value = "Deny" }
    allowedLocations = { value = ["eastus2", "centralus"] }
  })
}
