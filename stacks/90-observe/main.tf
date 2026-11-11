locals {
  topic_arn   = data.terraform_remote_state.events.outputs.topic_arn
  dlq_name    = data.terraform_remote_state.events.outputs.dlq_name
  ingest_fn   = data.terraform_remote_state.events.outputs.ingest_function_name
  instance_id = data.terraform_remote_state.ec2.outputs.instance_id
  cluster     = data.terraform_remote_state.ecs.outputs.cluster_name
  service     = data.terraform_remote_state.ecs.outputs.service_name
  alb_suffix  = data.terraform_remote_state.ecs.outputs.alb_arn_suffix
  tg_suffix   = data.terraform_remote_state.ecs.outputs.target_group_arn_suffix

  # Alarms on things that are switched off would sit in ALARM or INSUFFICIENT_DATA forever.
  has_service  = local.service != null
  has_instance = local.instance_id != null
}

# ------------------------------------------------------------ alarms, one per question the AWS series asked
resource "aws_cloudwatch_metric_alarm" "api_errors" {
  count = local.has_service ? 1 : 0

  alarm_name          = "plat-api-errors"
  alarm_description   = "The API returned 5 or more 5xx responses in 5 minutes"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = local.alb_suffix }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [local.topic_arn]
  ok_actions          = [local.topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "api_running_tasks" {
  count = local.has_service ? 1 : 0

  alarm_name          = "plat-api-running-tasks"
  alarm_description   = "Fewer than one API task is running"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  dimensions          = { ClusterName = local.cluster, ServiceName = coalesce(local.service, "none") }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [local.topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "ingest_errors" {
  alarm_name          = "plat-ingest-errors"
  alarm_description   = "plat-ingest reported an error"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = local.ingest_fn }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [local.topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "plat-dlq-not-empty"
  alarm_description   = "A message landed in the dead-letter queue"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = local.dlq_name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [local.topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "ec2_disk_high" {
  count = local.has_instance ? 1 : 0

  alarm_name          = "plat-ec2-data-disk-high"
  alarm_description   = "Root volume of plat-ec2 is above the threshold (metric comes from the CloudWatch agent)"
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  dimensions          = { InstanceId = coalesce(local.instance_id, "none"), path = "/" }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.disk_alarm_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [local.topic_arn]
}

# ------------------------------------------------------------ dashboard
locals {
  widgets = concat(
    [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Ingest Lambda: invocations and errors"
          region = var.region
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", local.ingest_fn],
            ["AWS/Lambda", "Errors", "FunctionName", local.ingest_fn],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Dead-letter queue depth"
          region = var.region
          stat   = "Maximum"
          period = 60
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.dlq_name],
          ]
        }
      },
    ],
    local.has_service ? [
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "API: requests and 5xx"
          region = var.region
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.alb_suffix],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "API: running tasks"
          region = var.region
          stat   = "Minimum"
          period = 60
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", local.cluster, "ServiceName", coalesce(local.service, "none")],
          ]
        }
      },
    ] : [],
    local.has_instance ? [
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "plat-ec2: disk and memory used (%)"
          region = var.region
          stat   = "Maximum"
          period = 300
          metrics = [
            ["CWAgent", "disk_used_percent", "InstanceId", coalesce(local.instance_id, "none"), "path", "/"],
            ["CWAgent", "mem_used_percent", "InstanceId", coalesce(local.instance_id, "none")],
          ]
        }
      },
    ] : [],
  )
}

resource "aws_cloudwatch_dashboard" "overview" {
  dashboard_name = "plat-overview"
  dashboard_body = jsonencode({ widgets = local.widgets })
}
