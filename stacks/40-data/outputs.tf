output "data_bucket" {
  value = module.data_bucket.id
}

output "data_bucket_arn" {
  value = module.data_bucket.arn
}

output "jobs_table_name" {
  value = aws_dynamodb_table.jobs.name
}

output "jobs_table_arn" {
  value = aws_dynamodb_table.jobs.arn
}

output "rds_endpoint" {
  value = one(aws_db_instance.meta[*].endpoint)
}

output "rds_secret_arn" {
  value = one(aws_db_instance.meta[*].master_user_secret[0].secret_arn)
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}

output "efs_id" {
  value = aws_efs_file_system.this.id
}

output "efs_access_point_arn" {
  value = aws_efs_access_point.ml.arn
}

output "efs_sg_id" {
  value = aws_security_group.efs.id
}

output "efs_access_point_id" {
  value = aws_efs_access_point.ml.id
}
