variable "region" {
  type    = string
  default = "us-east-1"
}

variable "alert_email" {
  description = "Address that receives plat-alerts. Leave empty to skip the subscription. You must click the confirmation link AWS emails you."
  type        = string
  default     = ""
}

variable "ttl_days" {
  description = "Days before an ingested job item expires."
  type        = number
  default     = 30
}

variable "report_cron" {
  description = "EventBridge cron (UTC). The default is 02:00 in Bengaluru."
  type        = string
  default     = "cron(30 20 * * ? *)"
}
