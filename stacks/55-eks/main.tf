locals {
  private    = values(data.terraform_remote_state.network.outputs.private_subnet_ids)
  kms_arn    = data.terraform_remote_state.security.outputs.kms_key_arn
  bucket_arn = data.terraform_remote_state.data.outputs.data_bucket_arn
  table_arn  = data.terraform_remote_state.data.outputs.jobs_table_arn
  secret_arn = data.terraform_remote_state.data.outputs.rds_secret_arn
  rds_sg_id  = data.terraform_remote_state.data.outputs.rds_sg_id
  create     = var.enable_eks ? 1 : 0
}

# ------------------------------------------------------------ cluster role and cluster
data "aws_iam_policy_document" "eks_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  count = local.create

  name               = "plat-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_trust.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  count = local.create

  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  count = local.create

  name     = "plat-eks"
  role_arn = aws_iam_role.cluster[0].arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = local.private
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # Access entries instead of the old aws-auth ConfigMap. The identity that creates the cluster
  # (you, as PlatformAdmin) is made cluster admin automatically.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# ------------------------------------------------------------ node group
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  count = local.create

  name               = "plat-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = var.enable_eks ? toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
  ]) : toset([])

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/${each.key}"
}

resource "aws_eks_node_group" "this" {
  count = local.create

  cluster_name    = aws_eks_cluster.this[0].name
  node_group_name = "plat-nodes"
  node_role_arn   = aws_iam_role.node[0].arn
  subnet_ids      = local.private
  instance_types  = [var.node_instance_type]
  ami_type        = "AL2023_x86_64_STANDARD"

  scaling_config {
    desired_size = var.node_desired
    min_size     = 1
    max_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  # Something else (the cluster autoscaler, or you) may change the desired size later.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

# ------------------------------------------------------------ pod role (EKS Pod Identity)
data "aws_iam_policy_document" "pods_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pod" {
  count = local.create

  name               = "plat-eks-pod-role"
  assume_role_policy = data.aws_iam_policy_document.pods_trust.json
}

data "aws_iam_policy_document" "pod_access" {
  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket"]
    resources = [local.bucket_arn]
  }

  statement {
    sid       = "ReadWriteObjects"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${local.bucket_arn}/*"]
  }

  statement {
    sid       = "JobsTable"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:Query"]
    resources = [local.table_arn, "${local.table_arn}/index/*"]
  }

  statement {
    sid       = "UseDataKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [local.kms_arn]
  }

  dynamic "statement" {
    for_each = local.secret_arn == null ? [] : [local.secret_arn]

    content {
      sid       = "ReadDbSecret"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "pod_access" {
  count = local.create

  name   = "plat-api-access"
  role   = aws_iam_role.pod[0].id
  policy = data.aws_iam_policy_document.pod_access.json
}

# The agent runs on every node and hands out the role's credentials to matching pods.
resource "aws_eks_addon" "pod_identity" {
  count = local.create

  cluster_name = aws_eks_cluster.this[0].name
  addon_name   = "eks-pod-identity-agent"

  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_pod_identity_association" "api" {
  count = local.create

  cluster_name    = aws_eks_cluster.this[0].name
  namespace       = "default"
  service_account = var.service_account
  role_arn        = aws_iam_role.pod[0].arn

  depends_on = [aws_eks_addon.pod_identity]
}

# ------------------------------------------------------------ let the pods reach RDS
resource "aws_vpc_security_group_ingress_rule" "rds_from_cluster" {
  count = local.create

  security_group_id            = local.rds_sg_id
  referenced_security_group_id = aws_eks_cluster.this[0].vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from EKS nodes and pods"
}
