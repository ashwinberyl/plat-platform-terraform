terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Values come from scripts/tf.sh (-backend-config), because a backend block cannot use variables.
  backend "s3" {}
}
