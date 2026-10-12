# Where the ComfyUI image comes from: the ECR repository, the build context uploaded to S3, and the CodeBuild
# project that builds it.
#
# Replaces the blueprint's DockerImageAsset, which cdk deploy built on whatever machine ran it - for this
# project, the old CodeBuild build after it had cloned the blueprint - and pushed to the CDK bootstrap stack's
# shared repository. Starting the build is not infrastructure; the root does that with an action.
resource "aws_ecr_repository" "comfyui" {
  name = var.repository_name
  # IMMUTABLE, as the CDK bootstrap repository is. Tags here are content hashes, so a tag never needs to
  # move, and the buildspec skips a tag that is already present instead of pushing over it.
  image_tag_mutability = "IMMUTABLE"
  # Every image in it was pushed by a build Terraform does not track, so without this destroy stops on
  # RepositoryNotEmptyException.
  force_delete = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}
# The build context's bucket. Its name is generated, because nothing reads it but the project below.
resource "aws_s3_bucket" "source" {
  bucket_prefix = "${substr(var.project_name, 0, 28)}-src-"
  # It holds one zip, which Terraform uploaded and can upload again.
  force_destroy = true
}
resource "aws_s3_bucket_public_access_block" "source" {
  bucket                  = aws_s3_bucket.source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# The build context, uploaded where the project reads it. source_hash is the content hash the root computes
# from the files rather than the zip's own checksum, so the same files zipped on another platform do not
# upload again (rules.md B-5).
resource "aws_s3_object" "source" {
  bucket      = aws_s3_bucket.source.id
  key         = var.source_object_key
  source      = var.source_zip_path
  source_hash = var.source_hash

  # S3 can reject a write that races the bucket's public access block with OperationAborted, and the bucket
  # reference alone does not wait for it (rules.md D-1).
  depends_on = [aws_s3_bucket_public_access_block.source]
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
# Scoped to the log group, the one source object and the one repository.
#
# This is the role that replaces the old deployment build's, which held AdministratorAccess because it ran
# cdk deploy on code cloned at build time and so needed whatever that code created. Building one image needs
# none of that (rules.md A-5).
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
        Resource = ["${aws_s3_bucket.source.arn}/${var.source_object_key}"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketAcl", "s3:GetBucketLocation"]
        Resource = [aws_s3_bucket.source.arn]
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
          "ecr:DescribeImages",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = [aws_ecr_repository.comfyui.arn]
      },
    ]
  })
}
resource "aws_codebuild_project" "build" {
  name          = var.project_name
  description   = "Builds the ComfyUI image from s3://${aws_s3_bucket.source.id}/${var.source_object_key} and pushes it to ${aws_ecr_repository.comfyui.repository_url}"
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
    # docker build and docker push need a Docker daemon inside the build container.
    privileged_mode = true

    # The buildspec reads all three. Set here, from the repository and the tag the task definition is given,
    # so the image that is pushed is the image that is pulled (rules.md B-5).
    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = aws_ecr_repository.comfyui.name
    }
    environment_variable {
      name  = "IMAGE_TAG"
      value = var.image_tag
    }
    environment_variable {
      name  = "IMAGE_URI"
      value = "${aws_ecr_repository.comfyui.repository_url}:${var.image_tag}"
    }
  }

  source {
    type      = "S3"
    location  = "${aws_s3_bucket.source.id}/${var.source_object_key}"
    buildspec = var.buildspec
  }

  # The role's policy has to be in place before a build starts, and service_role referencing the role does
  # not imply its inline policy (rules.md D-1).
  depends_on = [aws_iam_role_policy.build, aws_cloudwatch_log_group.build]
}
