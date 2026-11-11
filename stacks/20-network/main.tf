module "vpc" {
  source = "../../modules/vpc"

  name                 = "plat"
  cidr_block           = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat           = var.enable_nat
}

# Runs after apply and only warns: DNS hostnames are what make interface endpoints resolve (Post 05).
check "vpc_dns_hostnames" {
  data "aws_vpc" "this" {
    id = module.vpc.vpc_id
  }

  assert {
    condition     = data.aws_vpc.this.enable_dns_hostnames
    error_message = "DNS hostnames are off in the VPC. Interface endpoints with private DNS will not resolve."
  }
}
