variable "region" {
  type    = string
  default = "us-east-1"
}

variable "alert_email" {
  description = "Receives budget and anomaly emails. Budgets also publish to plat-alerts either way."
  type        = string
  default     = ""
}

variable "monthly_limit_usd" {
  description = "Limit for the whole-account budget."
  type        = string
  default     = "20"
}

variable "tagged_limit_usd" {
  description = "Limit for the budget that counts only resources tagged project = plat."
  type        = string
  default     = "15"
}

variable "enable_cost_allocation_tags" {
  description = "Activate the project tag for cost reports. Only works once the tag has appeared on a resource that incurred cost, usually after a day."
  type        = bool
  default     = false
}

variable "enable_anomaly_detection" {
  description = "Cost Anomaly Detection monitor and email subscription. Needs alert_email."
  type        = bool
  default     = false
}
