output "role_arn" {
  value = aws_iam_role.sagemaker.arn
}

output "domain_id" {
  value = one(aws_sagemaker_domain.studio[*].id)
}

output "studio_sg_id" {
  value = one(aws_security_group.studio[*].id)
}

output "endpoint_name" {
  value = one(aws_sagemaker_endpoint.churn[*].name)
}
