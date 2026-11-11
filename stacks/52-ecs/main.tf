locals {
  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
  public     = values(data.terraform_remote_state.network.outputs.public_subnet_ids)
  private    = values(data.terraform_remote_state.network.outputs.private_subnet_ids)
  kms_arn    = data.terraform_remote_state.security.outputs.kms_key_arn
  app_sg_id  = data.terraform_remote_state.security.outputs.app_sg_id
  bucket_arn = data.terraform_remote_state.data.outputs.data_bucket_arn
  bucket     = data.terraform_remote_state.data.outputs.data_bucket
  table_arn  = data.terraform_remote_state.data.outputs.jobs_table_arn
  table      = data.terraform_remote_state.data.outputs.jobs_table_name
  secret_arn = data.terraform_remote_state.data.outputs.rds_secret_arn
  rds_host   = data.terraform_remote_state.data.outputs.rds_endpoint
}

# ------------------------------------------------------------ image registry
resource "aws_ecr_repository" "api" {
  name                 = "plat-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = local.kms_arn
  }
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# ------------------------------------------------------------ cluster and logs
resource "aws_ecs_cluster" "this" {
  name = "plat-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/plat-api"
  retention_in_days = 14
}

# ------------------------------------------------------------ roles
data "aws_iam_policy_document" "tasks_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# The execution role belongs to ECS itself: pull the image, write logs.
resource "aws_iam_role" "exec" {
  name               = "plat-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.tasks_trust.json
}

resource "aws_iam_role_policy_attachment" "exec" {
  role       = aws_iam_role.exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The task role belongs to your code: what the running container may call.
resource "aws_iam_role" "task" {
  name               = "plat-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.tasks_trust.json
}

data "aws_iam_policy_document" "task_access" {
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

  # Both the bucket and the table are encrypted with the platform key, so callers need it too.
  statement {
    sid       = "UseDataKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [local.kms_arn]
  }

  # Only when RDS exists: its managed secret, and the key that encrypts it.
  dynamic "statement" {
    for_each = local.secret_arn == null ? [] : [local.secret_arn]

    content {
      sid       = "ReadDbSecret"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "task_access" {
  name   = "plat-api-access"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_access.json
}

# ------------------------------------------------------------ security groups
resource "aws_security_group" "alb" {
  name        = "plat-alb-sg"
  description = "Public entry to the load balancer"
  vpc_id      = local.vpc_id

  tags = { Name = "plat-alb-sg" }
}

resource "aws_security_group" "api" {
  name        = "plat-api-sg"
  description = "API tasks: traffic from the load balancer only"
  vpc_id      = local.vpc_id

  tags = { Name = "plat-api-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "HTTP from the internet"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_api" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.api.id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  description                  = "To the API tasks"
}

resource "aws_vpc_security_group_ingress_rule" "api_from_alb" {
  security_group_id            = aws_security_group.api.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  description                  = "From the load balancer"
}

resource "aws_vpc_security_group_egress_rule" "api_all" {
  security_group_id = aws_security_group.api.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

# ------------------------------------------------------------ task definition
resource "aws_ecs_task_definition" "api" {
  family                   = "plat-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.exec.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "api"
    image     = var.container_image
    essential = true

    portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]

    environment = [
      { name = "TABLE_NAME", value = local.table },
      { name = "BUCKET_NAME", value = local.bucket },
      { name = "DB_HOST", value = local.rds_host == null ? "" : local.rds_host },
      { name = "DB_SECRET_ARN", value = local.secret_arn == null ? "" : local.secret_arn },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.api.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "api"
      }
    }
  }])
}

# ------------------------------------------------------------ load balancer and service (toggle)
resource "aws_lb" "api" {
  count = var.enable_service ? 1 : 0

  name                       = "plat-alb"
  load_balancer_type         = "application"
  subnets                    = local.public
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "api" {
  count = var.enable_service ? 1 : 0

  name        = "plat-api-tg"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200-399"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  count = var.enable_service ? 1 : 0

  load_balancer_arn = aws_lb.api[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api[0].arn
  }
}

resource "aws_ecs_service" "api" {
  count = var.enable_service ? 1 : 0

  name                              = "plat-api-svc"
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.api.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 30

  network_configuration {
    subnets          = local.private
    security_groups  = [aws_security_group.api.id, local.app_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api[0].arn
    container_name   = "api"
    container_port   = var.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # The pipeline (Post 12) registers new task definition revisions, and an autoscaler may change the count.
  # Terraform creates the service and then stops fighting over those two fields.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.http]
}
