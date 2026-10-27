# ---------------------------------------------------------------------------
# Cost visibility and guardrails
# Problem: spend was visible only after the invoice, and nobody could say what
# was driving it. These resources create a feedback loop: warn early, report
# regularly, flag anomalies, and make every dollar attributable.
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "governance" {
  name     = "cost-governance-rg"
  location = "eastus"

  tags = {
    (var.required_tag) = "platform"
  }
}

# One reusable notification target. Add SMS, webhook or more people here later
# without touching the budget.
resource "azurerm_monitor_action_group" "cost" {
  name                = "cost-alerts-ag"
  resource_group_name = azurerm_resource_group.governance.name
  short_name          = "costalert"

  email_receiver {
    name                    = "budget-owner"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }

  tags = {
    (var.required_tag) = "platform"
  }
}

# Tiered budget: early actual warnings, plus FORECAST alerts that fire before
# the money is gone.
resource "azurerm_consumption_budget_subscription" "monthly" {
  name            = "monthly-subscription-budget"
  subscription_id = data.azurerm_subscription.current.id

  amount     = var.monthly_budget
  time_grain = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  notification {
    enabled        = true
    threshold      = 50
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_groups = [azurerm_monitor_action_group.cost.id]
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_groups = [azurerm_monitor_action_group.cost.id]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_groups = [azurerm_monitor_action_group.cost.id]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_groups = [azurerm_monitor_action_group.cost.id]
  }
}

# Saved Cost Analysis view: month-to-date spend grouped by resource group.
resource "azurerm_subscription_cost_management_view" "by_resource_group" {
  name            = "spend-by-resource-group"
  display_name    = "Month-to-date spend by resource group"
  subscription_id = data.azurerm_subscription.current.id

  chart_type  = "StackedColumn"
  accumulated = false
  report_type = "Usage"
  timeframe   = "MonthToDate"

  dataset {
    granularity = "Daily"

    aggregation {
      name        = "totalCost"
      column_name = "Cost"
    }

    grouping {
      name = "ResourceGroupName"
      type = "Dimension"
    }
  }

  # Non-table charts require exactly three pivots (the sub-views in Cost Analysis).
  pivot {
    type = "Dimension"
    name = "ResourceGroupName"
  }

  pivot {
    type = "Dimension"
    name = "ServiceName"
  }

  pivot {
    type = "TagKey"
    name = "cost-center"
  }
}

# A non-technical manager will not open the portal, so the report goes to them.
resource "azurerm_cost_management_scheduled_action" "weekly_report" {
  name         = "weekly-cost-report"
  display_name = "Weekly Azure cost report"
  view_id      = azurerm_subscription_cost_management_view.by_resource_group.id

  email_address_sender = var.alert_email
  email_subject        = "Weekly Azure cost report"
  email_addresses      = [var.alert_email]
  message              = "Month-to-date Azure spend by resource group."

  frequency     = "Weekly"
  days_of_week  = ["Monday"]
  hour_of_day   = 13
  start_date    = var.report_start_date
  end_date      = var.report_end_date
}

# Flags unusual daily spend, e.g. a forgotten resource, without waiting for the
# monthly total.
resource "azurerm_cost_anomaly_alert" "anomaly" {
  name            = "daily-anomaly-alert"
  display_name    = "Daily cost anomaly alert"
  subscription_id = data.azurerm_subscription.current.id
  email_subject   = "Azure cost anomaly detected"
  email_addresses = [var.alert_email]
}
