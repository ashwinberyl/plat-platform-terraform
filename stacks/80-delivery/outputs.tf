output "connection_arn" {
  value = aws_codestarconnections_connection.github.arn
}

output "connection_status" {
  description = "PENDING until someone authorises the connection in the console."
  value       = aws_codestarconnections_connection.github.connection_status
}

output "pipeline_name" {
  value = aws_codepipeline.api.name
}

output "build_project" {
  value = aws_codebuild_project.build.name
}

output "artifact_bucket" {
  value = module.artifacts.id
}
