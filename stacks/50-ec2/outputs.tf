output "instance_id" {
  value = one(aws_instance.this[*].id)
}

output "role_name" {
  value = aws_iam_role.ec2.name
}

output "role_arn" {
  value = aws_iam_role.ec2.arn
}
