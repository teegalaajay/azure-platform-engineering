# Management groups are an ARM scope above the subscription. They support no tags, so the
# mandatory-tag rule has nothing to attach to here (same exception as the budget, ADR-0011).
# No parent is set, so the group sits directly under the Tenant Root Group.
resource "azurerm_management_group" "platform" {
  name         = "mg-platform" # the ID: permanent, appears in every scope path below it
  display_name = "Platform"    # can be renamed later without recreating anything
}
