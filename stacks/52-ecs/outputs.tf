output "ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "ecr_repository_name" {
  value = aws_ecr_repository.api.name
}

output "ecr_repository_arn" {
  value = aws_ecr_repository.api.arn
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "service_name" {
  value = one(aws_ecs_service.api[*].name)
}

output "alb_dns_name" {
  value = one(aws_lb.api[*].dns_name)
}

output "alb_arn_suffix" {
  value = one(aws_lb.api[*].arn_suffix)
}

output "target_group_arn_suffix" {
  value = one(aws_lb_target_group.api[*].arn_suffix)
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "exec_role_arn" {
  value = aws_iam_role.exec.arn
}

output "task_definition_family" {
  value = aws_ecs_task_definition.api.family
}
