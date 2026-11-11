provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "plat"
      managed_by = "terraform"
      stack      = "95-cost"
    }
  }
}

data "aws_caller_identity" "current" {}
