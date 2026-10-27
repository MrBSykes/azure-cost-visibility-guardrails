# Attribution: every resource group must say who it belongs to, otherwise a
# cost spike cannot be traced to a project. Starts in Audit so existing
# untagged groups are reported, not broken. Switch to Deny after tagging them.

resource "azurerm_policy_definition" "require_tag_on_rg" {
  name         = "require-cost-tag-on-resource-groups"
  policy_type  = "Custom"
  mode         = "All" # Indexed mode skips resource groups
  display_name = "Resource groups must carry a cost attribution tag"

  metadata = jsonencode({ category = "Cost Management" })

  parameters = jsonencode({
    tagName = {
      type     = "String"
      metadata = { displayName = "Tag name" }
    }
    effect = {
      type          = "String"
      allowedValues = ["Audit", "Deny"]
      defaultValue  = "Audit"
      metadata      = { displayName = "Effect" }
    }
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        { field = "type", equals = "Microsoft.Resources/subscriptions/resourceGroups" },
        { field = "[concat('tags[', parameters('tagName'), ']')]", exists = "false" }
      ]
    }
    then = { effect = "[parameters('effect')]" }
  })
}

resource "azurerm_subscription_policy_assignment" "require_tag_on_rg" {
  name                 = "require-cost-tag-on-rg"
  display_name         = "Require cost attribution tag on resource groups"
  policy_definition_id = azurerm_policy_definition.require_tag_on_rg.id
  subscription_id      = data.azurerm_subscription.current.id

  parameters = jsonencode({
    tagName = { value = var.required_tag }
    effect  = { value = var.tag_policy_effect }
  })
}
