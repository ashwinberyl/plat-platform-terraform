output "topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "queue_url" {
  value = aws_sqs_queue.ingest.id
}

output "queue_name" {
  value = aws_sqs_queue.ingest.name
}

output "dlq_name" {
  value = aws_sqs_queue.dlq.name
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.id
}

output "ingest_function_name" {
  value = aws_lambda_function.ingest.function_name
}

output "report_function_name" {
  value = aws_lambda_function.report.function_name
}
