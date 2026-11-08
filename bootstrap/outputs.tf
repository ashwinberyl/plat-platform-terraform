output "state_bucket" {
  description = "Name of the S3 bucket that holds every other stack's state."
  value       = aws_s3_bucket.state.id
}

output "account_id" {
  value = local.account_id
}

output "plan_role_arn" {
  description = "Role for pull-request plans (set as the AWS_PLAN_ROLE_ARN repository variable)."
  value       = one(aws_iam_role.plan[*].arn)
}

output "apply_role_arn" {
  description = "Role for applies from main (set as the AWS_APPLY_ROLE_ARN repository variable)."
  value       = one(aws_iam_role.apply[*].arn)
}
