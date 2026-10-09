data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
# CodeBuild acting as a GitHub Actions self-hosted runner. The workflow's runs-on label names this project,
# GitHub sends a WORKFLOW_JOB_QUEUED webhook, and CodeBuild starts a container to run the job.
resource "aws_iam_role" "code_build_iam_role" {
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
# The _monolithic template attached AdministratorAccess to this role.
#
# That is a different case from the bastion's AdministratorAccess, which rules.md A-5 exempts: this is not
# a workbench a person is sitting at, it is a role assumed by a build that checks out and runs whatever is
# on a GitHub branch. The policy below is what the generated workflow actually needs, statement by
# statement, and the breadth it replaces is not visible in a plan - one policy ARN looks like any other.
#
# AdministratorAccess can be put back through additional_policy_arns, and the original behaviour is then
# one variable rather than a hidden default.
resource "aws_iam_role_policy" "code_build_iam_role" {
  count = var.create_runner_policy ? 1 : 0
  name  = var.policy_name
  role  = aws_iam_role.code_build_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EcrAuth"
        Effect = "Allow"
        # Not scopable to a repository - GetAuthorizationToken is an account-level call, which is why this
        # one statement has Resource "*".
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
          "ecr:DescribeImages",
        ]
        Resource = [var.ecr_repository_arn]
      },
      {
        Sid    = "EcsTaskDefinition"
        Effect = "Allow"
        # No resource-level permission exists for RegisterTaskDefinition: the definition being created does
        # not have an ARN yet, so ECS evaluates it against "*". Scoping it produces an AccessDenied that the
        # workflow reports as a failed render step with no detail.
        Action   = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"]
        Resource = "*"
      },
      {
        Sid      = "EcsService"
        Effect   = "Allow"
        Action   = ["ecs:DescribeServices"]
        Resource = ["arn:${data.aws_partition.current.partition}:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:service/${var.cluster_name}/${var.service_name}"]
      },
      {
        Sid    = "CodeDeploy"
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentGroup",
          "codedeploy:GetApplicationRevision",
          "codedeploy:RegisterApplicationRevision",
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:codedeploy:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:application:${var.code_deploy_application_name}",
          "arn:${data.aws_partition.current.partition}:codedeploy:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:deploymentgroup:${var.code_deploy_application_name}/${var.code_deploy_deployment_group_name}",
        ]
      },
      {
        Sid    = "CodeDeployConfig"
        Effect = "Allow"
        # The deployment configuration is an AWS-owned resource in this account's namespace, and
        # CodeDeployDefault.* configurations have to be named explicitly - the application ARN does not
        # cover them.
        Action   = ["codedeploy:GetDeploymentConfig"]
        Resource = ["arn:${data.aws_partition.current.partition}:codedeploy:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:deploymentconfig:${var.deployment_config_name}"]
      },
      {
        Sid    = "PassTaskRoles"
        Effect = "Allow"
        # Scoped to the two roles a task definition in this project may name, and conditioned on the
        # service they may be passed to. Both halves matter: without the resource list this is any role in
        # the account, and without the condition it is these roles passed to anything.
        Action   = ["iam:PassRole"]
        Resource = var.task_definition_role_arns
        Condition = {
          StringEquals = {
            "iam:PassedToService" = ["ecs-tasks.amazonaws.com"]
          }
        }
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.project_name}",
          "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.project_name}:*",
        ]
      },
    ]
  })
}
resource "aws_iam_role_policy_attachment" "code_build_iam_role" {
  for_each   = toset(var.additional_policy_arns)
  role       = aws_iam_role.code_build_iam_role.name
  policy_arn = each.value
}
resource "aws_codebuild_project" "runner" {
  name         = var.project_name
  description  = var.description
  service_role = aws_iam_role.code_build_iam_role.arn
  # NO_ARTIFACTS, as the _monolithic template had it: the job's output is an image in ECR and a CodeDeploy
  # deployment, not a build artefact CodeBuild should store.
  artifacts {
    type = "NO_ARTIFACTS"
  }
  environment {
    type         = var.environment_type
    compute_type = var.compute_type
    image        = var.build_image
    # The _monolithic template omitted this, and the workflow it generated runs docker build. Without a
    # Docker daemon in the build container that step fails with "Cannot connect to the Docker daemon", on
    # the GitHub side, minutes after an apply that reported success.
    privileged_mode = var.privileged_mode
  }
  source {
    type     = "GITHUB"
    location = var.repository_clone_url
    # No auth block. The _monolithic template carried
    #
    #   auth { type = "OAUTH", resource = <codestar connection id> }
    #
    # which the AWS provider deprecates in favour of aws_codebuild_source_credential - the resource the
    # github_source module creates, and the one a GITHUB-source project actually picks up. One credential
    # per (auth_type, server_type) applies to every project in the region, so there is nothing to name
    # here.
  }
  # A self-hosted runner project still needs a source version: without one CodeBuild has no revision to
  # start from when the webhook arrives. The _monolithic template omitted it.
  source_version = var.default_branch
  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
    }
  }
  # The source credential has to exist before a project whose source type is GITHUB can be created, and no
  # value reference says so - the credential is in another module, so the root carries that edge
  # (rules.md D-2).
}
# The part the conversion left as a TODO: the template carried Triggers with a WORKFLOW_JOB_QUEUED filter,
# and the AWS provider expresses it as a separate resource. Without it the project exists and nothing ever
# starts a build - the workflow sits queued, with no error on either side.
resource "aws_codebuild_webhook" "runner" {
  project_name = aws_codebuild_project.runner.name
  build_type   = "BUILD"
  filter_group {
    # WORKFLOW_JOB_QUEUED is what makes this a runner rather than an ordinary source-triggered build:
    # CodeBuild reacts to GitHub queueing a job for its label, not to a push.
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
