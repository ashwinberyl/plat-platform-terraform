output "dashboard_name" {
  value = aws_cloudwatch_dashboard.overview.dashboard_name
}

output "alarm_names" {
  value = concat(
    aws_cloudwatch_metric_alarm.api_errors[*].alarm_name,
    aws_cloudwatch_metric_alarm.api_running_tasks[*].alarm_name,
    aws_cloudwatch_metric_alarm.ec2_disk_high[*].alarm_name,
    [aws_cloudwatch_metric_alarm.ingest_errors.alarm_name, aws_cloudwatch_metric_alarm.dlq_not_empty.alarm_name],
  )
}
