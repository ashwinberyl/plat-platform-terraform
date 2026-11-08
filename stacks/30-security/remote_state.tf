locals {
  state_bucket = "plat-tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"
}

data "terraform_remote_state" "identity" {
  backend = "s3"

  config = {
    bucket = local.state_bucket
    key    = "10-identity/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = local.state_bucket
    key    = "20-network/terraform.tfstate"
    region = var.region
  }
}
