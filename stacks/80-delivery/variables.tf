variable "region" {
  type    = string
  default = "us-east-1"
}

variable "source_repo" {
  description = "GitHub repository (owner/name) that holds the API source and its Dockerfile."
  type        = string
  default     = "ashwinberyl/plat-platform"
}

variable "source_branch" {
  type    = string
  default = "main"
}

variable "enable_deploy_stage" {
  description = "Add the ECS deploy stage. Needs 52-ecs applied with enable_service = true."
  type        = bool
  default     = false
}
