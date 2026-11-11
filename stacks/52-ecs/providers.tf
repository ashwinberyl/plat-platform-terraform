provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "plat"
      managed_by = "terraform"
      stack      = "52-ecs"
    }
  }
}

data "aws_caller_identity" "current" {}
