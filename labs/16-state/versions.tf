terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Run with: scripts/tf.sh labs/16-state <command>
  backend "s3" {}
}
