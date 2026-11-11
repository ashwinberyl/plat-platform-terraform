locals {
  account_id   = data.aws_caller_identity.current.account_id
  repo_url     = data.terraform_remote_state.ecs.outputs.ecr_repository_url
  repo_arn     = data.terraform_remote_state.ecs.outputs.ecr_repository_arn
  cluster_name = data.terraform_remote_state.ecs.outputs.cluster_name
  service_name = data.terraform_remote_state.ecs.outputs.service_name
  task_role    = data.terraform_remote_state.ecs.outputs.task_role_arn
  exec_role    = data.terraform_remote_state.ecs.outputs.exec_role_arn
  topic_arn    = data.terraform_remote_state.events.outputs.topic_arn
  pipeline     = "plat-api-pipeline"
}

# ------------------------------------------------------------ GitHub connection
# Terraform creates it in the PENDING state. A person must authorise it once in the console (Post 12).
resource "aws_codestarconnections_connection" "github" {
  name          = "plat-github"
  provider_type = "GitHub"
}

# ------------------------------------------------------------ artifact bucket
module "artifacts" {
  source = "../../modules/s3-bucket"

  name          = "plat-pipeline-artifacts-${local.account_id}-${var.region}"
  versioning    = false
  force_destroy = true

  lifecycle_rules = [
    {
      id                              = "expire-artifacts"
      expiration_days                 = 14
      abort_incomplete_multipart_days = 1
    },
  ]
}

# ------------------------------------------------------------ CodeBuild
data "aws_iam_policy_document" "codebuild_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "build" {
  name               = "plat-api-build-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_trust.json
}

data "aws_iam_policy_document" "build" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.build.arn}:*"]
  }

  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [local.repo_arn]
  }

  statement {
    sid       = "Artifacts"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:GetBucketLocation"]
    resources = [module.artifacts.arn, "${module.artifacts.arn}/*"]
  }
}

resource "aws_iam_role_policy" "build" {
  name   = "plat-api-build-access"
  role   = aws_iam_role.build.id
  policy = data.aws_iam_policy_document.build.json
}

resource "aws_cloudwatch_log_group" "build" {
  name              = "/codebuild/plat-api-build"
  retention_in_days = 14
}

resource "aws_codebuild_project" "build" {
  name         = "plat-api-build"
  service_role = aws_iam_role.build.arn

  source {
    type = "CODEPIPELINE"

    buildspec = <<-EOT
      version: 0.2
      phases:
        pre_build:
          commands:
            - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $REPO_URL
            - IMAGE_TAG=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c1-8)
        build:
          commands:
            - docker build -t $REPO_URL:$IMAGE_TAG -t $REPO_URL:latest .
        post_build:
          commands:
            - docker push $REPO_URL:$IMAGE_TAG
            - docker push $REPO_URL:latest
            - printf '[{"name":"%s","imageUri":"%s"}]' $CONTAINER_NAME $REPO_URL:$IMAGE_TAG > imagedefinitions.json
      artifacts:
        files:
          - imagedefinitions.json
    EOT
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type            = "LINUX_CONTAINER"
    image           = "aws/codebuild/standard:7.0"
    compute_type    = "BUILD_GENERAL1_SMALL"
    privileged_mode = true # needed to run the Docker daemon

    environment_variable {
      name  = "REPO_URL"
      value = local.repo_url
    }

    environment_variable {
      name  = "CONTAINER_NAME"
      value = "api"
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build.name
    }
  }
}

# ------------------------------------------------------------ CodePipeline
data "aws_iam_policy_document" "pipeline_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pipeline" {
  name               = "plat-api-pipeline-role"
  assume_role_policy = data.aws_iam_policy_document.pipeline_trust.json
}

data "aws_iam_policy_document" "pipeline" {
  statement {
    sid       = "Artifacts"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"]
    resources = [module.artifacts.arn, "${module.artifacts.arn}/*"]
  }

  statement {
    sid       = "UseGithubConnection"
    actions   = ["codestar-connections:UseConnection"]
    resources = [aws_codestarconnections_connection.github.arn]
  }

  statement {
    sid       = "RunBuild"
    actions   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
    resources = [aws_codebuild_project.build.arn]
  }

  statement {
    sid = "DeployToEcs"
    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PassTaskRolesToEcs"
    actions   = ["iam:PassRole"]
    resources = [local.task_role, local.exec_role]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "pipeline" {
  name   = "plat-api-pipeline-access"
  role   = aws_iam_role.pipeline.id
  policy = data.aws_iam_policy_document.pipeline.json
}

resource "aws_codepipeline" "api" {
  name          = local.pipeline
  role_arn      = aws_iam_role.pipeline.arn
  pipeline_type = "V2"

  artifact_store {
    location = module.artifacts.id
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "GitHub"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn        = aws_codestarconnections_connection.github.arn
        FullRepositoryId     = var.source_repo
        BranchName           = var.source_branch
        OutputArtifactFormat = "CODE_ZIP"
        DetectChanges        = "true"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "DockerBuild"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }
    }
  }

  dynamic "stage" {
    for_each = var.enable_deploy_stage ? [1] : []

    content {
      name = "Deploy"

      action {
        name            = "EcsDeploy"
        category        = "Deploy"
        owner           = "AWS"
        provider        = "ECS"
        version         = "1"
        input_artifacts = ["build_output"]

        configuration = {
          ClusterName = local.cluster_name
          ServiceName = local.service_name
          FileName    = "imagedefinitions.json"
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = !var.enable_deploy_stage || local.service_name != null
      error_message = "enable_deploy_stage needs the ECS service: apply 52-ecs with -var enable_service=true first."
    }
  }
}

# ------------------------------------------------------------ tell plat-alerts when the pipeline fails
resource "aws_cloudwatch_event_rule" "pipeline_failed" {
  name        = "plat-pipeline-failed"
  description = "plat-api-pipeline execution failed"

  event_pattern = jsonencode({
    source        = ["aws.codepipeline"]
    "detail-type" = ["CodePipeline Pipeline Execution State Change"]
    detail = {
      state    = ["FAILED"]
      pipeline = [local.pipeline]
    }
  })
}

resource "aws_cloudwatch_event_target" "pipeline_failed" {
  rule = aws_cloudwatch_event_rule.pipeline_failed.name
  arn  = local.topic_arn
}
