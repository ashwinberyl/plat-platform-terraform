locals {
  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
  private    = values(data.terraform_remote_state.network.outputs.private_subnet_ids)
  kms_arn    = data.terraform_remote_state.security.outputs.kms_key_arn
  bucket_arn = data.terraform_remote_state.data.outputs.data_bucket_arn

  studio   = var.enable_studio ? 1 : 0
  endpoint = var.enable_endpoint && var.model_data_url != null ? 1 : 0
}

# ------------------------------------------------------------ execution role
data "aws_iam_policy_document" "sagemaker_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sagemaker" {
  name               = "plat-sm-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_trust.json
}

# The broad AWS-managed policy covers SageMaker itself. Our own data comes from the inline policy.
resource "aws_iam_role_policy_attachment" "sagemaker_full" {
  role       = aws_iam_role.sagemaker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

data "aws_iam_policy_document" "sm_data_access" {
  statement {
    sid       = "ListDataBucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [local.bucket_arn]
  }

  statement {
    sid       = "ReadWriteMlPrefixes"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.bucket_arn}/raw/*", "${local.bucket_arn}/processed/*", "${local.bucket_arn}/models/*"]
  }

  statement {
    sid       = "UseDataKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey", "kms:CreateGrant"]
    resources = [local.kms_arn]
  }
}

resource "aws_iam_role_policy" "sm_data_access" {
  name   = "plat-sm-data-access"
  role   = aws_iam_role.sagemaker.id
  policy = data.aws_iam_policy_document.sm_data_access.json
}

# ------------------------------------------------------------ Studio networking
resource "aws_security_group" "studio" {
  count = local.studio

  name        = "plat-studio-sg"
  description = "SageMaker Studio apps"
  vpc_id      = local.vpc_id

  tags = { Name = "plat-studio-sg" }
}

# Studio apps and the domain's file system talk to each other on many ports, so members of the group
# may reach each other freely. Nothing outside the group may reach in.
resource "aws_vpc_security_group_ingress_rule" "studio_self" {
  count = local.studio

  security_group_id            = aws_security_group.studio[0].id
  referenced_security_group_id = aws_security_group.studio[0].id
  ip_protocol                  = "-1"
  description                  = "Members of the group talk to each other"
}

resource "aws_vpc_security_group_egress_rule" "studio_all" {
  count = local.studio

  security_group_id = aws_security_group.studio[0].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound (needs the NAT gateway or VPC endpoints to leave the VPC)"
}

# ------------------------------------------------------------ Studio domain and users
resource "aws_sagemaker_domain" "studio" {
  count = local.studio

  domain_name             = "plat-studio"
  auth_mode               = "IAM"
  vpc_id                  = local.vpc_id
  subnet_ids              = local.private
  app_network_access_type = "VpcOnly"

  default_user_settings {
    execution_role  = aws_iam_role.sagemaker.arn
    security_groups = [aws_security_group.studio[0].id]
  }

  default_space_settings {
    execution_role  = aws_iam_role.sagemaker.arn
    security_groups = [aws_security_group.studio[0].id]
  }

  # Destroy the domain's EFS home directories with it. Without this they are orphaned and keep billing.
  retention_policy {
    home_efs_file_system = "Delete"
  }
}

resource "aws_sagemaker_user_profile" "this" {
  for_each = var.enable_studio ? var.studio_users : toset([])

  domain_id         = aws_sagemaker_domain.studio[0].id
  user_profile_name = each.key
}

# ------------------------------------------------------------ real-time endpoint (toggle)
resource "aws_sagemaker_model" "churn" {
  count = local.endpoint

  name_prefix        = "plat-churn-"
  execution_role_arn = aws_iam_role.sagemaker.arn

  primary_container {
    image          = var.inference_image
    model_data_url = var.model_data_url
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_sagemaker_endpoint_configuration" "churn" {
  count = local.endpoint

  name_prefix = "plat-churn-"

  production_variants {
    variant_name           = "AllTraffic"
    model_name             = aws_sagemaker_model.churn[0].name
    initial_instance_count = 1
    instance_type          = var.endpoint_instance_type
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_sagemaker_endpoint" "churn" {
  count = local.endpoint

  name                 = "plat-churn"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.churn[0].name
}
