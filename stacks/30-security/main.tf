locals {
  account_id = data.aws_caller_identity.current.account_id
  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
}

# ------------------------------------------------------------ KMS key
# The first statement is what lets IAM policies control the key at all (Post 05).
data "aws_iam_policy_document" "key" {
  statement {
    sid       = "EnableIamPolicies"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "data" {
  description             = "Shared encryption key for the Platform Lab"
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.key.json
}

resource "aws_kms_alias" "data" {
  name          = "alias/plat-data"
  target_key_id = aws_kms_key.data.key_id
}

# ------------------------------------------------------------ practice secret
resource "aws_secretsmanager_secret" "demo" {
  name                    = "plat/demo/api-key"
  description             = "Practice secret"
  kms_key_id              = aws_kms_key.data.arn
  recovery_window_in_days = var.secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "demo" {
  secret_id     = aws_secretsmanager_secret.demo.id
  secret_string = jsonencode({ api_key = "demo-12345" })
}

# ------------------------------------------------------------ security groups
# Groups are created empty; rules are separate resources so rules can reference groups.
resource "aws_security_group" "app" {
  name        = "plat-app-sg"
  description = "Clients: shells, EC2, Lambda, tasks"
  vpc_id      = local.vpc_id

  tags = { Name = "plat-app-sg" }
}

resource "aws_security_group" "vpce" {
  name        = "plat-vpce-sg"
  description = "Interface endpoint access"
  vpc_id      = local.vpc_id

  tags = { Name = "plat-vpce-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "vpce_from_app" {
  security_group_id            = aws_security_group.vpce.id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS from clients"
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

# ------------------------------------------------------------ interface endpoint (toggle)
resource "aws_vpc_endpoint" "secretsmanager" {
  count = var.enable_secretsmanager_endpoint ? 1 : 0

  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [data.terraform_remote_state.network.outputs.private_subnet_ids["a"]]
  security_group_ids  = [aws_security_group.vpce.id]

  tags = { Name = "plat-secretsmanager-vpce" }
}

# ------------------------------------------------------------ lab switch for plat-demo-reader
data "aws_iam_policy_document" "demo_reader_kms" {
  statement {
    sid       = "DecryptWithPlatData"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.data.arn]
  }
}

resource "aws_iam_role_policy" "demo_reader_kms" {
  count = var.grant_demo_reader_decrypt ? 1 : 0

  name   = "plat-kms-decrypt-demo"
  role   = data.terraform_remote_state.identity.outputs.demo_reader_role_name
  policy = data.aws_iam_policy_document.demo_reader_kms.json
}
