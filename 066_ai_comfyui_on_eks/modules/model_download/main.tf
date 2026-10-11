# The CodeBuild project that downloads the models from HuggingFace into the models bucket.
#
# Replaces the blueprint's ComfyuiModelDownload project plus test/download_models_codebuild.sh, which zipped
# the buildspec on the workbench, uploaded it next to the models and started the build. The buildspec is the
# whole input, so it is the project's inline buildspec here and there is nothing to upload.
#
# Models are data, not infrastructure: nothing here waits for them. The GPU nodes copy what is already in the
# bucket when they boot, and the sync Lambda copies everything that lands afterwards onto the nodes that are
# running - which is why the root starts this build without blocking the apply on it.
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
# The blueprint's ModelDownloadRole: read and write on the models bucket, logs on the build's own group.
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
        # ListBucket is what lets "aws s3 ls" in the buildspec tell a missing model (skip check fails, file is
        # downloaded) from a forbidden one - without it every check fails and every model is downloaded again.
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [var.models_bucket_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"]
        Resource = ["${var.models_bucket_arn}/*"]
      },
    ]
  })
}
resource "aws_codebuild_project" "build" {
  name          = var.project_name
  description   = "Downloads ComfyUI models from HuggingFace into s3://${var.models_bucket_name}"
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

    # The buildspec declares both with empty or default values; project variables take precedence over
    # buildspec ones (rules.md B-5).
    environment_variable {
      name  = "MODELS_BUCKET"
      value = var.models_bucket_name
    }
    environment_variable {
      name  = "MODEL_TIER"
      value = var.model_tier
    }
  }

  source {
    type      = "NO_SOURCE"
    buildspec = var.buildspec
  }

  # The role's policy has to exist before a build starts, and service_role referencing the role does not
  # imply the inline policy (rules.md D-1).
  depends_on = [aws_iam_role_policy.build, aws_cloudwatch_log_group.build]
}
