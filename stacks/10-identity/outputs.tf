output "sso_instance_arn" {
  value = local.instance_arn
}

output "identity_store_id" {
  value = local.identity_store_id
}

output "access_portal_hint" {
  description = "Find the portal URL in Identity Center, Settings."
  value       = "https://console.aws.amazon.com/singlesignon/home?region=${var.region}#!/settings"
}

output "demo_reader_role_name" {
  value = aws_iam_role.demo_reader.name
}

output "demo_reader_role_arn" {
  value = aws_iam_role.demo_reader.arn
}

output "group_ids" {
  value = { for k, g in aws_identitystore_group.this : k => g.group_id }
}
