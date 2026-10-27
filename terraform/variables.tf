variable "subscription_id" {
  description = "Azure subscription to govern. Pass with TF_VAR_subscription_id."
  type        = string
}

variable "alert_email" {
  description = "Who gets cost alerts and the weekly report (the budget owner). Pass with TF_VAR_alert_email."
  type        = string
}

variable "monthly_budget" {
  description = "Monthly budget in the subscription's billing currency."
  type        = number
  default     = 10
}

variable "budget_start_date" {
  description = "First day of the month the budget starts (must be the 1st)."
  type        = string
  default     = "2026-10-01T00:00:00Z"
}

variable "report_start_date" {
  description = "When the weekly report starts (UTC). Use a future Monday."
  type        = string
  default     = "2026-11-02T00:00:00Z"
}

variable "report_end_date" {
  description = "When the weekly report stops (UTC)."
  type        = string
  default     = "2027-11-01T00:00:00Z"
}

variable "required_tag" {
  description = "Tag every resource group should carry so spend can be attributed."
  type        = string
  default     = "cost-center"
}

variable "tag_policy_effect" {
  description = "Audit reports untagged resource groups; Deny blocks creating them. Start with Audit."
  type        = string
  default     = "Audit"

  validation {
    condition     = contains(["Audit", "Deny"], var.tag_policy_effect)
    error_message = "tag_policy_effect must be Audit or Deny."
  }
}
