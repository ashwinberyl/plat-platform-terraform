locals {
  state_bucket = "plat-tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"
}

data "terraform_remote_state" "ec2" {
  backend = "s3"

  config = {
    bucket = local.state_bucket
    key    = "50-ec2/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "ecs" {
  backend = "s3"

  config = {
    bucket = local.state_bucket
    key    = "52-ecs/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "events" {
  backend = "s3"

  config = {
    bucket = local.state_bucket
    key    = "60-events/terraform.tfstate"
    region = var.region
  }
}
