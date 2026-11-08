# Identity Center must already be enabled by hand (Post 03). Terraform can read it, not create it.
data "aws_ssoadmin_instances" "this" {}

locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
  account_id        = data.aws_caller_identity.current.account_id

  groups = toset(["platform-admins", "data-scientists"])

  # group name -> permission set name
  assignments = {
    "platform-admins" = "PlatformAdmin"
    "data-scientists" = "DataScientist"
  }

  # one entry per (user, group) pair
  memberships = merge([
    for username, u in var.users : {
      for g in u.groups : "${username}/${g}" => { user = username, group = g }
    }
  ]...)
}

# ------------------------------------------------------------ groups and users
resource "aws_identitystore_group" "this" {
  for_each = local.groups

  identity_store_id = local.identity_store_id
  display_name      = each.key
  description       = "Managed by Terraform"
}

resource "aws_identitystore_user" "this" {
  for_each = var.users

  identity_store_id = local.identity_store_id
  user_name         = each.key
  display_name      = "${each.value.given_name} ${each.value.family_name}"

  name {
    given_name  = each.value.given_name
    family_name = each.value.family_name
  }

  emails {
    value   = each.value.email
    primary = true
  }
}

resource "aws_identitystore_group_membership" "this" {
  for_each = local.memberships

  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.this[each.value.group].group_id
  member_id         = aws_identitystore_user.this[each.value.user].user_id
}

# ------------------------------------------------------------ permission sets
resource "aws_ssoadmin_permission_set" "platform_admin" {
  name             = "PlatformAdmin"
  description      = "Full administration for the platform team"
  instance_arn     = local.instance_arn
  session_duration = var.admin_session_duration
}

resource "aws_ssoadmin_managed_policy_attachment" "platform_admin" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.platform_admin.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_ssoadmin_permission_set" "data_scientist" {
  name             = "DataScientist"
  description      = "Read-mostly access for data scientists"
  instance_arn     = local.instance_arn
  session_duration = var.scientist_session_duration
}

resource "aws_ssoadmin_managed_policy_attachment" "data_scientist" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.data_scientist.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

locals {
  permission_set_arns = {
    PlatformAdmin = aws_ssoadmin_permission_set.platform_admin.arn
    DataScientist = aws_ssoadmin_permission_set.data_scientist.arn
  }
}

# ------------------------------------------------------------ group -> account
resource "aws_ssoadmin_account_assignment" "this" {
  for_each = local.assignments

  instance_arn       = local.instance_arn
  permission_set_arn = local.permission_set_arns[each.value]

  principal_id   = aws_identitystore_group.this[each.key].group_id
  principal_type = "GROUP"

  target_id   = local.account_id
  target_type = "AWS_ACCOUNT"

  depends_on = [
    aws_ssoadmin_managed_policy_attachment.platform_admin,
    aws_ssoadmin_managed_policy_attachment.data_scientist,
  ]
}

# ------------------------------------------------------------ plat-demo-reader
# The guinea-pig role from Post 02, rebuilt as code. It trusts the account, so any
# principal in the account whose own policy allows sts:AssumeRole can use it.
data "aws_iam_policy_document" "demo_reader_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "demo_reader" {
  name                 = "plat-demo-reader"
  description          = "Practice role for IAM, key policy and bucket policy labs"
  assume_role_policy   = data.aws_iam_policy_document.demo_reader_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "demo_reader_s3" {
  statement {
    sid       = "ListDataBucket"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::plat-data-${local.account_id}-${var.region}"]
  }

  statement {
    sid       = "ReadDataObjects"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::plat-data-${local.account_id}-${var.region}/*"]
  }
}

resource "aws_iam_role_policy" "demo_reader_s3" {
  name   = "plat-s3-read-demo"
  role   = aws_iam_role.demo_reader.id
  policy = data.aws_iam_policy_document.demo_reader_s3.json
}
