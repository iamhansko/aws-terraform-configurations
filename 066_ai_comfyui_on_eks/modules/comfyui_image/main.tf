# Where the ComfyUI image comes from: the ECR repositories, the build context uploaded to S3, the CodeBuild
# project that builds it, and the weekly rebuild.
#
# Replaces the blueprint's ComfyUI-on-EKS-ECR stack plus comfyui_image/build_and_push.sh, which zipped the
# build context on the workbench, copied it to S3 and polled the build in a loop. The context is now part of
# this project (comfyui_image/ at the root) and the upload is a resource, so editing the Dockerfile or a
# custom node is a plan diff. Starting the build is not infrastructure - the root does that with an action.
resource "aws_ecr_repository" "comfyui" {
  name                 = var.repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}
resource "aws_ecr_repository" "base_cache" {
  name                 = var.base_cache_repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}
locals {
  # The blueprint's lifecycleRules: [{ maxImageCount: 10 }], applied to both repositories. The base cache had
  # none in the blueprint and grew by one untagged image every week.
  lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the ${var.max_image_count} most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.max_image_count
      }
      action = { type = "expire" }
    }]
  })
}
resource "aws_ecr_lifecycle_policy" "comfyui" {
  repository = aws_ecr_repository.comfyui.name
  policy     = local.lifecycle_policy
}
resource "aws_ecr_lifecycle_policy" "base_cache" {
  repository = aws_ecr_repository.base_cache.name
  policy     = local.lifecycle_policy
}
# The build context, uploaded where the project reads it. source_hash re-uploads it whenever the zip's
# contents change, which is the half of "edit the Dockerfile and apply" that build_and_push.sh used to do.
resource "aws_s3_object" "build_source" {
  bucket      = var.source_bucket_name
  key         = var.source_object_key
  source      = var.source_zip_path
  source_hash = var.source_zip_hash
}
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
# Scoped to the two repositories, the log group and the one source object.
#
# The blueprint's role attached AmazonEC2ContainerRegistryPowerUser, which pushes to every repository in the
# account, plus ecr:CreateRepository on comfyui-* so the buildspec could create its base cache. The cache
# exists before any build here, so creating repositories is not something this role needs at all - only
# DescribeRepositories, which is how the buildspec checks for it (rules.md A-5).
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
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = ["${var.source_bucket_arn}/${var.source_object_key}"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation", "s3:GetBucketAcl"]
        Resource = [var.source_bucket_arn]
      },
      {
        # Account-wide by necessity: the token is not scoped to a repository, and ECR has no resource for it.
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = [aws_ecr_repository.comfyui.arn, aws_ecr_repository.base_cache.arn]
      },
    ]
  })
}
resource "aws_codebuild_project" "build" {
  name          = var.project_name
  description   = "Builds the ComfyUI image from the build context in s3://${var.source_bucket_name}/${var.source_object_key} and pushes it to ${aws_ecr_repository.comfyui.repository_url}"
  service_role  = aws_iam_role.build.arn
  build_timeout = var.build_timeout_minutes

  artifacts {
    type = "NO_ARTIFACTS"
  }

  logs_config {
    cloudwatch_logs {
      status     = "ENABLED"
      group_name = aws_cloudwatch_log_group.build.name
    }
  }

  environment {
    type         = "LINUX_CONTAINER"
    compute_type = var.compute_type
    image        = var.build_image
    # The build runs docker build and docker push, which need a Docker daemon inside the build container.
    privileged_mode = true

    # The buildspec declares defaults for all three; project variables take precedence over buildspec ones,
    # so these are what the build actually uses and the names live in one place (rules.md B-5).
    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = aws_ecr_repository.comfyui.name
    }
    environment_variable {
      name  = "IMAGE_TAG"
      value = var.image_tag
    }
    environment_variable {
      name  = "BASE_CACHE_REPO"
      value = aws_ecr_repository.base_cache.name
    }
  }

  # The zip carries buildspec.yml at its root, which CodeBuild uses when the project names none.
  source {
    type     = "S3"
    location = "${var.source_bucket_name}/${var.source_object_key}"
  }

  # The role's policy has to exist before a build starts, and service_role referencing the role does not
  # imply the inline policy (rules.md D-1).
  depends_on = [aws_iam_role_policy.build, aws_cloudwatch_log_group.build]
}
# The blueprint's WeeklyImageRebuild.
resource "aws_iam_role" "rebuild_schedule" {
  count = var.rebuild_schedule_expression == null ? 0 : 1

  name_prefix = "${substr(var.project_name, 0, 24)}-sched-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy" "rebuild_schedule" {
  count = var.rebuild_schedule_expression == null ? 0 : 1

  name = "start-build"
  role = aws_iam_role.rebuild_schedule[0].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "codebuild:StartBuild"
      Resource = aws_codebuild_project.build.arn
    }]
  })
}
resource "aws_cloudwatch_event_rule" "rebuild_schedule" {
  count = var.rebuild_schedule_expression == null ? 0 : 1

  name                = "${var.project_name}-weekly-rebuild"
  description         = "Rebuilds the ComfyUI image to pick up base image and OS security patches"
  schedule_expression = var.rebuild_schedule_expression
}
resource "aws_cloudwatch_event_target" "rebuild_schedule" {
  count = var.rebuild_schedule_expression == null ? 0 : 1

  rule     = aws_cloudwatch_event_rule.rebuild_schedule[0].name
  arn      = aws_codebuild_project.build.arn
  role_arn = aws_iam_role.rebuild_schedule[0].arn

  # The target's role has to be allowed to start the build before the first scheduled run, and role_arn does
  # not imply its inline policy (rules.md D-1).
  depends_on = [aws_iam_role_policy.rebuild_schedule]
}
