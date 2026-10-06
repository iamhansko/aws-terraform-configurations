data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# CodeBuild acting as a GitHub Actions self-hosted runner. The workflow's runs-on
# label names this project, GitHub sends a WORKFLOW_JOB_QUEUED webhook, and CodeBuild
# starts a container to run the job.
#
# The credential is account-and-region scoped, not project scoped: one
# aws_codebuild_source_credential per (auth_type, server_type) pair applies to every
# CodeBuild project in the region. It lives here anyway because nothing else in this
# project uses CodeBuild, and because a project whose source is GITHUB cannot be
# created before it exists.
resource "aws_codebuild_source_credential" "github" {
  auth_type   = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token       = var.github_token
}
resource "aws_iam_role" "codebuild" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["codebuild.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
# The _monolithic template attached AdministratorAccess to this role. What the build
# actually does is log in to ECR, push an image, and write CloudWatch logs, so the
# policy below is scoped to that. AdministratorAccess on a role assumed by a build
# that runs code from a public repository is worth avoiding even in a demo.
resource "aws_iam_role_policy" "codebuild" {
  name = var.policy_name
  role = aws_iam_role.codebuild.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EcrAuth"
        Effect = "Allow"
        # GetAuthorizationToken is not scopable to a repository - it is an account-level
        # call, which is why this one statement has Resource "*".
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = [var.ecr_repository_arn]
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.project_name}",
          "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.project_name}:*",
        ]
      },
    ]
  })
}
resource "aws_codebuild_project" "runner" {
  name         = var.project_name
  description  = var.description
  service_role = aws_iam_role.codebuild.arn

  # NO_ARTIFACTS because the job's output is an image in ECR and a commit in GitHub,
  # not a build artifact CodeBuild should store.
  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    type            = var.environment_type
    compute_type    = var.compute_type
    image           = var.build_image
    privileged_mode = var.privileged_mode
  }

  source {
    type     = "GITHUB"
    location = var.repository_clone_url
  }

  # Required for a self-hosted runner: without it CodeBuild has no source version to
  # start from when the webhook arrives.
  source_version = var.default_branch

  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
    }
  }

  # The credential has to exist before a project whose source type is GITHUB can be
  # created, and nothing in the value references says so (rules.md D-1).
  depends_on = [aws_codebuild_source_credential.github]
}
# The part the CloudFormation conversion left as a TODO: the template carried
# Triggers with a WORKFLOW_JOB_QUEUED filter and the AWS provider expresses it as a
# separate resource. Without it the project exists but nothing ever starts a build,
# and the workflow sits queued with no error on either side.
resource "aws_codebuild_webhook" "runner" {
  project_name = aws_codebuild_project.runner.name
  # WORKFLOW_JOB_QUEUED is what makes this a runner rather than an ordinary
  # source-triggered build: CodeBuild reacts to GitHub queueing a job for its label,
  # not to a push.
  build_type = "BUILD"

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "WORKFLOW_JOB_QUEUED"
    }
    filter {
      type    = "WORKFLOW_NAME"
      pattern = var.workflow_name
    }
  }
}
