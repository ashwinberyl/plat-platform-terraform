variable "region" {
  type    = string
  default = "us-east-1"
}

variable "enable_service" {
  description = "Create the load balancer and the Fargate service. The ALB and each task bill every hour."
  type        = bool
  default     = false
}

variable "container_image" {
  description = "Image for the first task definition. The default is a public nginx so the service works before you push your own image to ECR."
  type        = string
  default     = "public.ecr.aws/docker/library/nginx:stable"
}

variable "container_port" {
  description = "Port the container listens on. nginx uses 80; set 8080 for the API image."
  type        = number
  default     = 80
}

variable "health_check_path" {
  type    = string
  default = "/"
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}
