provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "plat"
      managed_by = "terraform"
      stack      = "70-ml"
    }
  }
}

data "aws_caller_identity" "current" {}
