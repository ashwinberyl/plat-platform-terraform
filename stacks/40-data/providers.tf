provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "plat"
      managed_by = "terraform"
      stack      = "40-data"
    }
  }
}

data "aws_caller_identity" "current" {}
