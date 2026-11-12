locals {
  account_id = data.aws_caller_identity.current.account_id
  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
  private    = data.terraform_remote_state.network.outputs.private_subnet_ids
  kms_arn    = data.terraform_remote_state.security.outputs.kms_key_arn
  app_sg_id  = data.terraform_remote_state.security.outputs.app_sg_id
}

# ------------------------------------------------------------ data lake bucket (Post 06)
module "data_bucket" {
  source = "../../modules/s3-bucket"

  name          = "plat-data-${local.account_id}-${var.region}"
  kms_key_arn   = local.kms_arn
  force_destroy = var.force_destroy_bucket
  prefixes      = ["raw/", "processed/", "models/"]

  lifecycle_rules = [
    {
      id                              = "housekeeping"
      noncurrent_expiration_days      = 30
      abort_incomplete_multipart_days = 7
    },
    {
      id                       = "raw-to-ia"
      prefix                   = "raw/"
      transition_days          = 30
      transition_storage_class = "STANDARD_IA"
    },
  ]
}

# ------------------------------------------------------------ DynamoDB plat-jobs (Post 08)
resource "aws_dynamodb_table" "jobs" {
  name         = "plat-jobs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "job_id"

  deletion_protection_enabled = var.jobs_table_deletion_protection

  attribute {
    name = "job_id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  global_secondary_index {
    name            = "status-created_idx"
    projection_type = "ALL"

    key_schema {
      attribute_name = "status"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "created_at"
      key_type       = "RANGE"
    }
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = local.kms_arn
  }
}

# ------------------------------------------------------------ RDS plat-meta (Post 08)
resource "aws_db_subnet_group" "meta" {
  count = var.enable_rds ? 1 : 0

  name        = "plat-db-subnets"
  description = "Private subnets for plat-meta"
  subnet_ids  = values(local.private)

  tags = { Name = "plat-db-subnets" }
}

resource "aws_security_group" "rds" {
  name        = "plat-rds-sg"
  description = "PostgreSQL from clients"
  vpc_id      = local.vpc_id

  tags = { Name = "plat-rds-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_app" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = local.app_sg_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from clients"
}

resource "aws_db_instance" "meta" {
  count = var.enable_rds ? 1 : 0

  identifier     = "plat-meta"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = local.kms_arn

  db_name  = var.restore_snapshot_identifier == null ? "platmeta" : null
  username = var.restore_snapshot_identifier == null ? "platadmin" : null

  manage_master_user_password   = true
  master_user_secret_kms_key_id = local.kms_arn

  snapshot_identifier = var.restore_snapshot_identifier

  db_subnet_group_name   = aws_db_subnet_group.meta[0].name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period   = 1
  skip_final_snapshot       = var.rds_skip_final_snapshot
  final_snapshot_identifier = var.rds_skip_final_snapshot ? null : "plat-meta-final"
  deletion_protection       = false
  apply_immediately         = true

  tags = { Name = "plat-meta" }
}

# ------------------------------------------------------------ EFS plat-efs (Post 07)
resource "aws_security_group" "efs" {
  name        = "plat-efs-sg"
  description = "NFS access to EFS"
  vpc_id      = local.vpc_id

  tags = { Name = "plat-efs-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_app" {
  security_group_id            = aws_security_group.efs.id
  referenced_security_group_id = local.app_sg_id
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  description                  = "NFS from clients"
}

resource "aws_efs_file_system" "this" {
  creation_token   = "plat-efs"
  encrypted        = true
  kms_key_id       = local.kms_arn
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = { Name = "plat-efs" }
}

resource "aws_efs_mount_target" "this" {
  for_each = local.private

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "ml" {
  file_system_id = aws_efs_file_system.this.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/ml"

    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  tags = { Name = "plat-ml-ap" }
}

data "aws_iam_policy_document" "efs" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["*"]
    resources = [aws_efs_file_system.this.arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # With no policy EFS lets any client with network access in; keep that, add only the TLS rule.
  statement {
    sid       = "AllowNetworkClients"
    actions   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
    resources = [aws_efs_file_system.this.arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }
}

resource "aws_efs_file_system_policy" "this" {
  file_system_id = aws_efs_file_system.this.id
  policy         = data.aws_iam_policy_document.efs.json
}
