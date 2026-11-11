output "cluster_name" {
  value = one(aws_eks_cluster.this[*].name)
}

output "cluster_endpoint" {
  value = one(aws_eks_cluster.this[*].endpoint)
}

output "pod_role_arn" {
  value = one(aws_iam_role.pod[*].arn)
}

output "kubeconfig_command" {
  value = var.enable_eks ? "aws eks update-kubeconfig --name plat-eks --region ${var.region}" : null
}
