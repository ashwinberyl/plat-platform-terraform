# Post 16 lab: bring a bucket someone created by hand under Terraform, then practise state surgery.
variable "region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name" {
  description = "Name of the hand-made bucket (see the lab for the command that creates it)."
  type        = string
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "plat"
      managed_by = "terraform"
      stack      = "lab-16-state"
    }
  }
}

output "bucket_name" {
  description = "Echoes the hand-made bucket name that import.tf.example adopts."
  value       = var.bucket_name
}
