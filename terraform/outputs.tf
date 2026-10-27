output "budget_name" {
  value = azurerm_consumption_budget_subscription.monthly.name
}

output "action_group_id" {
  value = azurerm_monitor_action_group.cost.id
}
