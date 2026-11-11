locals {
  private      = data.terraform_remote_state.network.outputs.private_subnet_ids
  vpc_id       = data.terraform_remote_state.network.outputs.vpc_id
  kms_arn      = data.terraform_remote_state.security.outputs.kms_key_arn
  app_sg_id    = data.terraform_remote_state.security.outputs.app_sg_id
  vpce_sg_id   = data.terraform_remote_state.security.outputs.vpce_sg_id
  bucket_arn   = data.terraform_remote_state.data.outputs.data_bucket_arn
  efs_id       = data.terraform_remote_state.data.outputs.efs_id
  efs_ap_id    = data.terraform_remote_state.data.outputs.efs_access_point_id
  cwagent_name = "AmazonCloudWatch-plat"
}

# Always the newest Amazon Linux 2023 AMI. AWS publishes the current id under this public parameter.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ------------------------------------------------------------ role and profile
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "plat-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

# Session Manager and the CloudWatch agent. The agent policy can read parameters named AmazonCloudWatch-*.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cwagent" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

data "aws_iam_policy_document" "ec2_data_access" {
  statement {
    sid       = "ListDataBucket"
    actions   = ["s3:ListBucket"]
    resources = [local.bucket_arn]
  }

  statement {
    sid       = "ReadWriteObjects"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${local.bucket_arn}/*"]
  }

  statement {
    sid       = "UseDataKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [local.kms_arn]
  }
}

resource "aws_iam_role_policy" "ec2_data_access" {
  name   = "plat-ec2-data-access"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_data_access.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = "plat-ec2-role"
  role = aws_iam_role.ec2.name
}

# ------------------------------------------------------------ CloudWatch agent configuration
resource "aws_ssm_parameter" "cwagent" {
  name = local.cwagent_name
  type = "String"

  value = jsonencode({
    agent = { metrics_collection_interval = 60 }
    metrics = {
      append_dimensions      = { InstanceId = "$${aws:InstanceId}" }
      aggregation_dimensions = [["InstanceId", "path"]]
      metrics_collected = {
        disk = {
          measurement              = ["used_percent"]
          resources                = ["/"]
          ignore_file_system_types = ["sysfs", "devtmpfs", "tmpfs"]
        }
        mem = { measurement = ["mem_used_percent"] }
      }
    }
  })
}

# ------------------------------------------------------------ the instance
resource "aws_instance" "this" {
  count = var.enable_ec2 ? 1 : 0

  ami                    = data.aws_ssm_parameter.al2023.insecure_value
  instance_type          = var.instance_type
  subnet_id              = local.private["a"]
  vpc_security_group_ids = [local.app_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/userdata.sh.tftpl", {
    mount_efs       = var.mount_efs
    efs_id          = local.efs_id
    access_point_id = local.efs_ap_id
    cwagent_param   = local.cwagent_name
  })

  # IMDSv2 only: requests to the metadata service must carry a session token.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  tags = { Name = "plat-ec2" }

  # A newer AMI is published every few weeks. Do not replace a running instance because of it.
  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [aws_ssm_parameter.cwagent]
}

# ------------------------------------------------------------ Session Manager without a NAT (toggle)
resource "aws_vpc_endpoint" "ssm" {
  for_each = var.enable_ssm_endpoints ? toset(["ssm", "ssmmessages", "ec2messages"]) : toset([])

  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [local.private["a"]]
  security_group_ids  = [local.vpce_sg_id]

  tags = { Name = "plat-${each.key}-vpce" }
}
