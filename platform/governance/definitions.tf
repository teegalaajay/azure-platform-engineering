# Custom policy definition at the management group scope. The effect is a parameter so the same
# definition runs as Audit first and Deny later without being edited (ADR-0040).
resource "azurerm_policy_definition" "storage_shared_key_disabled" {
  name                = "storage-shared-key-disabled"
  display_name        = "Storage accounts must have shared key access disabled"
  policy_type         = "Custom"
  mode                = "Indexed"
  management_group_id = azurerm_management_group.platform.id

  metadata = jsonencode({ category = "Storage" })

  parameters = jsonencode({
    effect = {
      type = "String"
      metadata = {
        displayName = "Effect"
        description = "Audit reports non-compliant accounts; Deny rejects the request; Disabled switches the rule off."
      }
      allowedValues = ["Audit", "Deny", "Disabled"]
      defaultValue  = "Audit"
    }
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        { field = "type", equals = "Microsoft.Storage/storageAccounts" },
        {
          anyOf = [
            { field = "Microsoft.Storage/storageAccounts/allowSharedKeyAccess", exists = "false" },
            { field = "Microsoft.Storage/storageAccounts/allowSharedKeyAccess", notEquals = false }
          ]
        }
      ]
    }
    then = { effect = "[parameters('effect')]" }
  })
}
