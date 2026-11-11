locals {
  account_id = data.aws_caller_identity.current.account_id
  kms_arn    = data.terraform_remote_state.security.outputs.kms_key_arn
  bucket     = data.terraform_remote_state.data.outputs.data_bucket
  bucket_arn = data.terraform_remote_state.data.outputs.data_bucket_arn
  table      = data.terraform_remote_state.data.outputs.jobs_table_name
  table_arn  = data.terraform_remote_state.data.outputs.jobs_table_arn
}

# ============================================================ alerts: SNS
resource "aws_sns_topic" "alerts" {
  name = "plat-alerts"
}

data "aws_iam_policy_document" "alerts" {
  statement {
    sid       = "OwnerAccount"
    actions   = ["sns:Publish", "sns:Subscribe", "sns:GetTopicAttributes", "sns:SetTopicAttributes", "sns:ListSubscriptionsByTopic"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "EventsAndAlarmsMayPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "BudgetsMayPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts.json
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ============================================================ ingest: S3 -> SQS -> Lambda -> DynamoDB
resource "aws_sqs_queue" "dlq" {
  name                      = "plat-ingest-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "ingest" {
  name                       = "plat-ingest-queue"
  visibility_timeout_seconds = 60
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

data "aws_iam_policy_document" "queue" {
  statement {
    sid       = "S3MaySend"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.ingest.arn]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [local.bucket_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_sqs_queue_policy" "ingest" {
  queue_url = aws_sqs_queue.ingest.id
  policy    = data.aws_iam_policy_document.queue.json
}

# One notification configuration per bucket. This stack owns it, the bucket itself belongs to 40-data.
resource "aws_s3_bucket_notification" "raw" {
  bucket = local.bucket

  queue {
    queue_arn     = aws_sqs_queue.ingest.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "raw/"
  }

  depends_on = [aws_sqs_queue_policy.ingest]
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ingest" {
  name               = "plat-ingest-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "ingest_logs" {
  role       = aws_iam_role.ingest.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "ingest_access" {
  statement {
    sid       = "ReadQueue"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.ingest.arn]
  }

  statement {
    sid       = "ReadRawObjects"
    actions   = ["s3:GetObject"]
    resources = ["${local.bucket_arn}/raw/*"]
  }

  statement {
    sid       = "WriteJobs"
    actions   = ["dynamodb:PutItem"]
    resources = [local.table_arn]
  }

  statement {
    sid       = "UseDataKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [local.kms_arn]
  }
}

resource "aws_iam_role_policy" "ingest_access" {
  name   = "plat-ingest-access"
  role   = aws_iam_role.ingest.id
  policy = data.aws_iam_policy_document.ingest_access.json
}

data "archive_file" "ingest" {
  type        = "zip"
  source_file = "${path.module}/src/ingest.py"
  output_path = "${path.module}/ingest.zip"
}

resource "aws_cloudwatch_log_group" "ingest" {
  name              = "/aws/lambda/plat-ingest"
  retention_in_days = 14
}

resource "aws_lambda_function" "ingest" {
  function_name    = "plat-ingest"
  role             = aws_iam_role.ingest.arn
  runtime          = "python3.12"
  handler          = "ingest.handler"
  filename         = data.archive_file.ingest.output_path
  source_code_hash = data.archive_file.ingest.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      TABLE_NAME = local.table
      TTL_DAYS   = tostring(var.ttl_days)
    }
  }

  depends_on = [aws_cloudwatch_log_group.ingest, aws_iam_role_policy_attachment.ingest_logs]
}

resource "aws_lambda_event_source_mapping" "ingest" {
  event_source_arn        = aws_sqs_queue.ingest.arn
  function_name           = aws_lambda_function.ingest.arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]

  depends_on = [aws_iam_role_policy.ingest_access]
}

# ============================================================ nightly report: EventBridge schedule -> Lambda -> SNS
resource "aws_iam_role" "report" {
  name               = "plat-report-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "report_logs" {
  role       = aws_iam_role.report.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "report_access" {
  statement {
    sid       = "ScanJobs"
    actions   = ["dynamodb:Scan"]
    resources = [local.table_arn]
  }

  statement {
    sid       = "Publish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid       = "UseDataKey"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [local.kms_arn]
  }
}

resource "aws_iam_role_policy" "report_access" {
  name   = "plat-report-access"
  role   = aws_iam_role.report.id
  policy = data.aws_iam_policy_document.report_access.json
}

data "archive_file" "report" {
  type        = "zip"
  source_file = "${path.module}/src/report.py"
  output_path = "${path.module}/report.zip"
}

resource "aws_cloudwatch_log_group" "report" {
  name              = "/aws/lambda/plat-report"
  retention_in_days = 14
}

resource "aws_lambda_function" "report" {
  function_name    = "plat-report"
  role             = aws_iam_role.report.arn
  runtime          = "python3.12"
  handler          = "report.handler"
  filename         = data.archive_file.report.output_path
  source_code_hash = data.archive_file.report.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      TABLE_NAME = local.table
      TOPIC_ARN  = aws_sns_topic.alerts.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.report, aws_iam_role_policy_attachment.report_logs]
}

resource "aws_cloudwatch_event_rule" "nightly" {
  name                = "plat-nightly-report"
  description         = "Run plat-report every night"
  schedule_expression = var.report_cron
}

resource "aws_cloudwatch_event_target" "nightly" {
  rule = aws_cloudwatch_event_rule.nightly.name
  arn  = aws_lambda_function.report.arn
}

resource "aws_lambda_permission" "nightly" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.report.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.nightly.arn
}

# ============================================================ instance state changes -> SNS
resource "aws_cloudwatch_event_rule" "ec2_state" {
  name        = "plat-ec2-state-change"
  description = "Tell plat-alerts when any EC2 instance starts, stops or terminates"

  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
    detail        = { state = ["running", "stopped", "terminated"] }
  })
}

resource "aws_cloudwatch_event_target" "ec2_state" {
  rule = aws_cloudwatch_event_rule.ec2_state.name
  arn  = aws_sns_topic.alerts.arn

  depends_on = [aws_sns_topic_policy.alerts]
}
