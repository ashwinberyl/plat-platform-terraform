provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "plat"
      managed_by = "terraform"
      stack      = "bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "plat-tfstate-${local.account_id}-${var.region}"
}

# ---------------------------------------------------------------- state bucket
resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Versioning is what lets you roll back a bad state file.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}

# ---------------------------------------------------------------- GitHub OIDC
locals {
  github_oidc_url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider && var.enable_ci_roles ? 1 : 0

  url            = local.github_oidc_url
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = !var.create_oidc_provider && var.enable_ci_roles ? 1 : 0

  url = local.github_oidc_url
}

locals {
  oidc_provider_arn = var.enable_ci_roles ? (
    var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
  ) : null
  github_sub_prefix = "repo:${var.github_owner}/${var.github_repo}"
}

# Plan role: any pull request in this repository may assume it. Read-only.
data "aws_iam_policy_document" "plan_trust" {
  count = var.enable_ci_roles ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_sub_prefix}:pull_request"]
    }
  }
}

# Apply role: only the main branch may assume it.
data "aws_iam_policy_document" "apply_trust" {
  count = var.enable_ci_roles ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_sub_prefix}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "plan" {
  count = var.enable_ci_roles ? 1 : 0

  name                 = "plat-tf-plan"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust[0].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  count = var.enable_ci_roles ? 1 : 0

  role       = aws_iam_role.plan[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# A plan still has to take the state lock, which writes a .tflock object.
data "aws_iam_policy_document" "plan_state" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "ReadWriteStateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  count = var.enable_ci_roles ? 1 : 0

  name   = "state-bucket"
  role   = aws_iam_role.plan[0].id
  policy = data.aws_iam_policy_document.plan_state.json
}

resource "aws_iam_role" "apply" {
  count = var.enable_ci_roles ? 1 : 0

  name                 = "plat-tf-apply"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust[0].json
  max_session_duration = 3600
}

# Two modes, chosen by var.apply_role_scoped (Post 18).
#   false: AdministratorAccess. Simple, and far too broad for anything real.
#   true : PowerUserAccess (everything except IAM and Organizations) plus IAM limited to plat-* names,
#          and an explicit Deny so the role can never edit the CI roles themselves.
resource "aws_iam_role_policy_attachment" "apply_admin" {
  count = var.enable_ci_roles && !var.apply_role_scoped ? 1 : 0

  role       = aws_iam_role.apply[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy_attachment" "apply_power_user" {
  count = var.enable_ci_roles && var.apply_role_scoped ? 1 : 0

  role       = aws_iam_role.apply[0].name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "apply_scoped_iam" {
  statement {
    sid     = "ManagePlatIam"
    actions = ["iam:*"]

    resources = [
      "arn:aws:iam::${local.account_id}:role/plat-*",
      "arn:aws:iam::${local.account_id}:policy/plat-*",
      "arn:aws:iam::${local.account_id}:instance-profile/plat-*",
    ]
  }

  statement {
    sid       = "ReadIamAndCreateServiceLinkedRoles"
    actions   = ["iam:Get*", "iam:List*", "iam:CreateServiceLinkedRole", "iam:SimulatePrincipalPolicy"]
    resources = ["*"]
  }

  statement {
    sid       = "OrganizationsReadForIdentityCenter"
    actions   = ["organizations:Describe*", "organizations:List*"]
    resources = ["*"]
  }

  statement {
    sid       = "NeverTouchTheCiRoles"
    effect    = "Deny"
    actions   = ["iam:*"]
    resources = ["arn:aws:iam::${local.account_id}:role/plat-tf-*"]
  }
}

resource "aws_iam_role_policy" "apply_scoped_iam" {
  count = var.enable_ci_roles && var.apply_role_scoped ? 1 : 0

  name   = "plat-scoped-iam"
  role   = aws_iam_role.apply[0].id
  policy = data.aws_iam_policy_document.apply_scoped_iam.json
}
