# Initiative (policy set definition): one assignment, one compliance view, one name for the
# baseline. Two members: our custom storage rule and the built-in Allowed locations (ADR-0040).
resource "azurerm_management_group_policy_set_definition" "platform_baseline" {
  name                = "platform-baseline"
  display_name        = "Platform baseline"
  policy_type         = "Custom"
  management_group_id = azurerm_management_group.platform.id

  metadata = jsonencode({ category = "Platform" })

  # One effect knob for the whole initiative: start at Audit, move to Deny after the audit review.
  parameters = jsonencode({
    effect = {
      type          = "String"
      allowedValues = ["Audit", "Deny", "Disabled"]
      defaultValue  = "Audit"
    }
    allowedLocations = {
      type         = "Array"
      defaultValue = ["eastus2", "centralus"]
    }
  })

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.storage_shared_key_disabled.id
    reference_id         = "storage-shared-key-disabled"
    parameter_values = jsonencode({
      effect = { value = "[parameters('effect')]" }
    })
  }

  policy_definition_reference {
    policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
    reference_id         = "allowed-locations"
    parameter_values = jsonencode({
      effect                 = { value = "[parameters('effect')]" }
      listOfAllowedLocations = { value = "[parameters('allowedLocations')]" }
    })
  }
}
