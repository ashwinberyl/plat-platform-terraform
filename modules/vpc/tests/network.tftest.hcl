# terraform -chdir=modules/vpc test
mock_provider "aws" {}

variables {
  azs                  = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24"]
  private_subnet_cidrs = ["10.20.10.0/24", "10.20.11.0/24"]
}

run "no_nat_by_default" {
  command = plan

  assert {
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_eip.nat) == 0 && length(aws_route.private_nat) == 0
    error_message = "The NAT gateway, its address and its route must not exist unless enable_nat is true."
  }

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2
    error_message = "Two public and two private subnets."
  }

  assert {
    condition     = contains(keys(aws_subnet.private), "a") && contains(keys(aws_subnet.private), "b")
    error_message = "Subnets must be keyed by AZ letter."
  }

  assert {
    condition     = length(aws_vpc_endpoint.gateway) == 2
    error_message = "S3 and DynamoDB gateway endpoints by default."
  }
}

run "nat_on" {
  command = plan

  variables {
    enable_nat = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1 && length(aws_eip.nat) == 1 && length(aws_route.private_nat) == 1
    error_message = "enable_nat = true creates one NAT gateway, one address and one route."
  }
}

run "cidr_count_must_match_azs" {
  command = plan

  variables {
    public_subnet_cidrs = ["10.20.0.0/24"]
  }

  expect_failures = [var.public_subnet_cidrs]
}

run "unsupported_endpoint_rejected" {
  command = plan

  variables {
    gateway_endpoints = ["s3", "kinesis"]
  }

  expect_failures = [var.gateway_endpoints]
}
