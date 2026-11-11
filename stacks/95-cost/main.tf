locals {
  topic_arn  = data.terraform_remote_state.events.outputs.topic_arn
  subscriber = var.alert_email == "" ? [] : [var.alert_email]
}

# ------------------------------------------------------------ whole-account budget
resource "aws_budgets_budget" "monthly" {
  name         = "plat-monthly-guard"
  budget_type  = "COST"
  limit_amount = var.monthly_limit_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = local.subscriber
    subscriber_sns_topic_arns  = [local.topic_arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = local.subscriber
    subscriber_sns_topic_arns  = [local.topic_arn]
  }
}

# ------------------------------------------------------------ only what this project tagged
resource "aws_budgets_budget" "tagged" {
  name         = "plat-tagged-monthly"
  budget_type  = "COST"
  limit_amount = var.tagged_limit_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:project$plat"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = local.subscriber
    subscriber_sns_topic_arns  = [local.topic_arn]
  }
}

# ------------------------------------------------------------ cost allocation tags (toggle)
resource "aws_ce_cost_allocation_tag" "this" {
  for_each = var.enable_cost_allocation_tags ? toset(["project", "managed_by", "stack"]) : toset([])

  tag_key = each.key
  status  = "Active"
}

# ------------------------------------------------------------ anomaly detection (toggle)
resource "aws_ce_anomaly_monitor" "services" {
  count = var.enable_anomaly_detection ? 1 : 0

  name              = "plat-services"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "email" {
  count = var.enable_anomaly_detection && var.alert_email != "" ? 1 : 0

  name             = "plat-anomaly-alerts"
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.services[0].arn]

  subscriber {
    type    = "EMAIL"
    address = var.alert_email
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["5"]
    }
  }
}
