data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Where the built image lands.
#
# force_delete, as the _monolithic template set it: ECR refuses to delete a repository that
# still holds images, and every image in here was pushed by a build Terraform does not track -
# so without it terraform destroy stops on a repository it cannot empty.
resource "aws_ecr_repository" "mcp_server" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    # On, which the _monolithic template left off. The image installs a Python toolchain and
    # a package from PyPI, so a basic scan on push is the cheapest thing that will ever say
    # anything about it.
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# A declared log group rather than the one CodeBuild creates implicitly, so the retention is
# set and the build role's permissions can be scoped to it.
resource "aws_cloudwatch_log_group" "build" {
  name              = "/aws/codebuild/${var.project_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "build" {
  name_prefix = "${substr(var.project_name, 0, 32)}-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# An inline policy naming this repository and this log group.
#
# The _monolithic template's build role had no policy at all - not AWSCodeBuildDeveloperAccess,
# not an inline statement, nothing - so the build could not write a log line, could not call
# ecr:GetAuthorizationToken, and failed in its pre_build phase on the docker login.
resource "aws_iam_role_policy" "build" {
  name = "build"
  role = aws_iam_role.build.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.build.arn}:*"]
      },
      {
        # Account-wide by necessity: the token is not scoped to a repository, and ECR has no
        # resource for it.
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        # Scoped to this one repository, which is the part that can be scoped (rules.md A-5).
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
        Resource = aws_ecr_repository.mcp_server.arn
      },
    ]
  })
}

locals {
  # The buildspec lives here rather than inline in the resource so that one expression can be both
  # the project's definition and the thing a caller hashes to decide whether to start a new build
  # (rules.md B-5). See the build_revision output.
  buildspec = <<-EOT
    version: 0.2
    phases:
      install:
        commands:
          - echo ${base64encode(var.dockerfile)} | base64 -d > Dockerfile
          - cat Dockerfile
      pre_build:
        commands:
          - aws ecr get-login-password --region ${data.aws_region.current.region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com
      build:
        commands:
          - docker build -t ${var.repository_name}:${var.image_tag} .
          - docker tag ${var.repository_name}:${var.image_tag} ${aws_ecr_repository.mcp_server.repository_url}:${var.image_tag}
      post_build:
        commands:
          - docker push ${aws_ecr_repository.mcp_server.repository_url}:${var.image_tag}
  EOT
}

resource "aws_codebuild_project" "build" {
  name          = var.project_name
  service_role  = aws_iam_role.build.arn
  build_timeout = var.build_timeout_minutes

  artifacts {
    type = "NO_ARTIFACTS"
  }

  logs_config {
    cloudwatch_logs {
      status      = "ENABLED"
      group_name  = aws_cloudwatch_log_group.build.name
      stream_name = "build"
    }
  }

  environment {
    type         = "LINUX_CONTAINER"
    compute_type = var.compute_type
    image        = var.build_image
    # Required: the build runs docker build and docker push, which need a Docker daemon in
    # the build container.
    privileged_mode = true
  }

  source {
    type = "NO_SOURCE"
    # The Dockerfile arrives as a value the caller read with file(), written out on the build
    # host. NO_SOURCE means there is no repository to read it from, which is why it has to
    # travel inside the buildspec at all.
    #
    # It travels base64-encoded, on one line, and that is not tidiness - it is the only shape
    # that survives being a multi-line value inside a buildspec. What was here before was a
    # quoted shell heredoc inside a YAML block scalar:
    #
    #     - |
    #       cat << 'TFDOCKERFILE' > Dockerfile
    #       ${var.dockerfile}
    #       TFDOCKERFILE
    #
    # and it could not work. Terraform computes an indented heredoc's dedent from the template
    # *source* lines only, so an interpolated multi-line value has its first line placed by the
    # template and every line after it at column 0 (rules.md E-9 relies on exactly this, because
    # there the value lands in a shell script where a terminator has to reach column 0). Here the
    # value lands inside a YAML block scalar, where indentation is structure. So the Dockerfile's
    # second line onwards escaped the scalar, YAML read "FROM ghcr.io/..." as a top-level key, and
    # CodeBuild failed the build in DOWNLOAD_SOURCE with
    #
    #     could not find expected ':' at line 15
    #
    # which names the buildspec rather than the Dockerfile and says nothing about indentation.
    # Nothing downstream survives that: ECR stays empty, the Deployment's pod sits in
    # ImagePullBackOff, and the SSM step that waits for the image never writes its marker.
    #
    # base64encode produces a single line with no newlines, so there is no indentation to get
    # wrong, no delimiter to collide with, and nothing for the shell to expand - the "$PATH" and
    # the JSON inside the Dockerfile arrive untouched. indent(8, ...) would also have parsed, but
    # it hard-codes this block's current indentation into the module: re-indent the buildspec and
    # the build breaks again, at build time rather than at plan time.
    #
    # "cat Dockerfile" stays. It is what keeps the real contents visible in the build log, which
    # is the readability the encoding costs.
    buildspec = local.buildspec
  }

  # The role's policy has to exist before a build starts, and service_role referencing the
  # role does not imply the inline policy (rules.md D-1).
  depends_on = [aws_iam_role_policy.build, aws_cloudwatch_log_group.build]
}
