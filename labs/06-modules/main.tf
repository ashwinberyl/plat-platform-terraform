# Post 06 lab. Calls the s3-bucket module three times. Local state, destroyed at the end of the lab.
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "plat"
      managed_by = "terraform"
      stack      = "lab-06-modules"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  suffix = "${data.aws_caller_identity.current.account_id}-${var.region}"
}

# One call, every feature on.
module "logs" {
  source = "../../modules/s3-bucket"

  name          = "plat-lab-logs-${local.suffix}"
  force_destroy = true
  prefixes      = ["app/", "alb/"]

  lifecycle_rules = [
    {
      id                              = "expire-logs"
      expiration_days                 = 30
      noncurrent_expiration_days      = 7
      abort_incomplete_multipart_days = 7
    },
  ]
}

# One call, two buckets: for_each on a module.
module "scratch" {
  source   = "../../modules/s3-bucket"
  for_each = toset(["one", "two"])

  name          = "plat-lab-scratch-${each.key}-${local.suffix}"
  versioning    = false
  force_destroy = true
}

output "buckets" {
  value = merge(
    { logs = module.logs.id },
    { for k, m in module.scratch : "scratch-${k}" => m.id },
  )
}
