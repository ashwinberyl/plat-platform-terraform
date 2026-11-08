output "kms_key_arn" {
  value = aws_kms_key.data.arn
}

output "kms_key_id" {
  value = aws_kms_key.data.key_id
}

output "kms_alias" {
  value = aws_kms_alias.data.name
}

output "demo_secret_arn" {
  value = aws_secretsmanager_secret.demo.arn
}

output "app_sg_id" {
  value = aws_security_group.app.id
}

output "vpce_sg_id" {
  value = aws_security_group.vpce.id
}
