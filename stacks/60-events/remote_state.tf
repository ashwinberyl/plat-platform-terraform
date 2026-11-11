locals {
  state_bucket = "plat-tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"
}

data "terraform_remote_state" "security" {
  backend = "s3"

  config = {
    bucket = local.state_bucket
    key    = "30-security/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "data" {
  backend = "s3"

  config = {
    bucket = local.state_bucket
    key    = "40-data/terraform.tfstate"
    region = var.region
  }
}
