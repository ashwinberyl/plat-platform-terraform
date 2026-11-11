provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "plat"
      managed_by = "terraform"
      stack      = "50-ec2"
    }
  }
}

data "aws_caller_identity" "current" {}
