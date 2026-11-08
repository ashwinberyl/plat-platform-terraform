data "aws_region" "current" {}

locals {
  az_suffix = [for az in var.azs : substr(az, length(az) - 1, 1)]

  public = {
    for i, az in var.azs : local.az_suffix[i] => {
      az   = az
      cidr = var.public_subnet_cidrs[i]
    }
  }

  private = {
    for i, az in var.azs : local.az_suffix[i] => {
      az   = az
      cidr = var.private_subnet_cidrs[i]
    }
  }

  first_az = local.az_suffix[0]

  endpoint_names = {
    s3       = "s3-gw"
    dynamodb = "ddb-gw"
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.name}-vpc" })

  lifecycle {
    precondition {
      condition     = length(var.azs) == length(var.public_subnet_cidrs) && length(var.azs) == length(var.private_subnet_cidrs)
      error_message = "Give exactly one public and one private CIDR per AZ."
    }
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-igw" })
}

resource "aws_subnet" "public" {
  for_each = local.public

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value.az
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = false

  tags = merge(var.tags, { Name = "${var.name}-public-${each.key}", tier = "public" })
}

resource "aws_subnet" "private" {
  for_each = local.private

  vpc_id            = aws_vpc.this.id
  availability_zone = each.value.az
  cidr_block        = each.value.cidr

  tags = merge(var.tags, { Name = "${var.name}-private-${each.key}", tier = "private" })
}

# ------------------------------------------------------------ route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-public-rt" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-private-rt" })
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# ------------------------------------------------------------ NAT (toggle)
resource "aws_eip" "nat" {
  count = var.enable_nat ? 1 : 0

  domain = "vpc"

  tags = merge(var.tags, { Name = "${var.name}-nat-eip" })
}

resource "aws_nat_gateway" "this" {
  count = var.enable_nat ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[local.first_az].id

  tags = merge(var.tags, { Name = "${var.name}-nat-${local.first_az}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "private_nat" {
  count = var.enable_nat ? 1 : 0

  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

# ------------------------------------------------------------ gateway endpoints
resource "aws_vpc_endpoint" "gateway" {
  for_each = var.gateway_endpoints

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(var.tags, { Name = "${var.name}-${local.endpoint_names[each.key]}" })
}
