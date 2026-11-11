provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "plat"
      managed_by = "terraform"
      stack      = "80-delivery"
    }
  }
}

data "aws_caller_identity" "current" {}
