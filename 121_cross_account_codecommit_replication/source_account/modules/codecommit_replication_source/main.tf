locals {
  pipeline_arn    = "arn:${var.partition}:codepipeline:${var.source_region}:${var.source_account_id}:${var.pipeline_name}"
  target_role_arn = "arn:${var.partition}:iam::${var.target_account_id}:role/${var.cross_account_role_name}"
}

resource "aws_codecommit_repository" "source" {
  repository_name = var.source_account_repository
  description     = "Source repository mirrored to ${var.target_account_id}/${var.target_account_repository}"

  # An empty CodeCommit repository has no branch, so default_branch cannot be set yet. The create-only
  # source_initial_commit below establishes main_branch before CodePipeline is allowed to exist.
}

# The AWS provider exposes default_branch but no CodeCommit file/commit resource. default_branch only selects
# a branch that already exists, so it cannot solve the empty-repository bootstrap. This create-only step uses
# the same source-account credentials as Terraform to call PutFile before pipeline creation. If the requested
# branch already exists it is deliberately a no-op: after bootstrap, Git—not Terraform—owns repository content.
resource "terraform_data" "source_initial_commit" {
  input = {
    repository_name = aws_codecommit_repository.source.repository_name
    branch_name     = var.main_branch
    file_path       = var.initial_commit_file_path
  }

  triggers_replace = [
    aws_codecommit_repository.source.repository_id,
    var.main_branch,
  ]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      AWS_REGION             = var.source_region
      AWS_DEFAULT_REGION     = var.source_region
      REPOSITORY_NAME        = aws_codecommit_repository.source.repository_name
      BRANCH_NAME            = var.main_branch
      INITIAL_FILE_PATH      = var.initial_commit_file_path
      INITIAL_FILE_CONTENT   = var.initial_commit_file_content
      INITIAL_COMMIT_MESSAGE = var.initial_commit_message
    }
    command = <<-EOT
      set -euo pipefail

      attempt=0
      until aws codecommit get-repository --repository-name "$REPOSITORY_NAME" >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [ "$attempt" -ge 30 ]; then
          echo "CodeCommit repository $REPOSITORY_NAME was not readable after 60 seconds" >&2
          exit 1
        fi
        sleep 2
      done

      if aws codecommit get-branch --repository-name "$REPOSITORY_NAME" --branch-name "$BRANCH_NAME" >/dev/null 2>&1; then
        echo "CodeCommit branch $REPOSITORY_NAME/$BRANCH_NAME already exists; leaving Git content unchanged"
        exit 0
      fi

      default_branch=$(aws codecommit get-repository --repository-name "$REPOSITORY_NAME" --query 'repositoryMetadata.defaultBranch' --output text)
      if [ -n "$default_branch" ] && [ "$default_branch" != "None" ] && [ "$default_branch" != "null" ]; then
        parent_commit=$(aws codecommit get-branch --repository-name "$REPOSITORY_NAME" --branch-name "$default_branch" --query 'branch.commitId' --output text)
        aws codecommit create-branch --repository-name "$REPOSITORY_NAME" --branch-name "$BRANCH_NAME" --commit-id "$parent_commit"
      else
        aws --cli-binary-format raw-in-base64-out codecommit put-file \
          --repository-name "$REPOSITORY_NAME" \
          --branch-name "$BRANCH_NAME" \
          --file-path "$INITIAL_FILE_PATH" \
          --file-content "$INITIAL_FILE_CONTENT" \
          --commit-message "$INITIAL_COMMIT_MESSAGE" \
          --name "Terraform" \
          --email "terraform@example.invalid" \
          >/dev/null
      fi

      aws codecommit get-branch --repository-name "$REPOSITORY_NAME" --branch-name "$BRANCH_NAME" >/dev/null
      echo "CodeCommit branch $REPOSITORY_NAME/$BRANCH_NAME is ready before CodePipeline creation"
      EOT
  }

  depends_on = [aws_codecommit_repository.source]
}

resource "aws_s3_bucket" "artifacts" {
  bucket_prefix = var.artifact_bucket_prefix
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudwatch_log_group" "build" {
  name              = "/aws/codebuild/${var.build_project_name}"
  retention_in_days = var.build_log_retention_days
}

resource "aws_iam_role" "build" {
  # This is intentionally the one fixed same-account service-role name: the independently applied target
  # trust policy names its exact ARN (rules.md I-2). All other service roles below use generated prefixes.
  name = var.source_codebuild_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "build" {
  name = "CodeCommitReplicationBuild"
  role = aws_iam_role.build.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteBuildLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.build.arn}:*"
      },
      {
        Sid      = "CloneSourceMirror"
        Effect   = "Allow"
        Action   = ["codecommit:GitPull"]
        Resource = aws_codecommit_repository.source.arn
      },
      {
        Sid      = "ReadPipelineInputArtifact"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },
      {
        Sid      = "ReadArtifactBucketLocation"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation"]
        Resource = aws_s3_bucket.artifacts.arn
      },
      {
        Sid      = "AssumeExactTargetRole"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = local.target_role_arn
      },
    ]
  })

  depends_on = [aws_iam_role.build]
}

resource "aws_codebuild_project" "mirror" {
  name          = var.build_project_name
  description   = "Mirrors every Git ref from ${var.source_region}/${var.source_account_repository} to ${var.target_region}/${var.target_account_repository}"
  service_role  = aws_iam_role.build.arn
  build_timeout = var.build_timeout_minutes

  # CodeBuild requires CODEPIPELINE here whenever its source type is CODEPIPELINE, even though the pipeline
  # build action intentionally declares no output artifact. This is the service integration contract, not
  # a request to upload a build result.
  artifacts {
    type = "CODEPIPELINE"
  }

  logs_config {
    cloudwatch_logs {
      status     = "ENABLED"
      group_name = aws_cloudwatch_log_group.build.name
    }
  }

  environment {
    type                        = "LINUX_CONTAINER"
    compute_type                = var.codebuild_compute_type
    image                       = var.codebuild_image
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false

    environment_variable {
      name  = "SOURCE_REGION"
      value = var.source_region
    }
    environment_variable {
      name  = "SOURCE_REPOSITORY"
      value = aws_codecommit_repository.source.repository_name
    }
    environment_variable {
      name  = "TARGET_REGION"
      value = var.target_region
    }
    environment_variable {
      name  = "TARGET_REPOSITORY"
      value = var.target_account_repository
    }
    environment_variable {
      name  = "TARGET_ROLE_ARN"
      value = local.target_role_arn
    }
    environment_variable {
      name  = "AWS_DNS_SUFFIX"
      value = var.dns_suffix
    }
  }

  source {
    type = "CODEPIPELINE"

    # The pipeline ZIP is only the trigger/input contract. Replication clones the repository itself as a
    # bare mirror, preserving commits, dotfiles, branches, tags, and deletions. A no-change --mirror push
    # exits successfully, and an empty target is a normal first push.
    buildspec = yamlencode({
      version = "0.2"
      env = {
        # standard:7.0 defaults buildspec commands to /bin/sh; the mirror uses pipefail and Bash's
        # here-string for the temporary STS credentials.
        shell = "bash"
      }
      phases = {
        build = {
          commands = [
            "set -euo pipefail",
            "export HOME=/tmp/codecommit-replication-home",
            "rm -rf \"$HOME\" /tmp/source-mirror.git",
            "mkdir -p \"$HOME\"",
            "git config --global credential.helper '!aws codecommit credential-helper $@'",
            "git config --global credential.UseHttpPath true",
            "export AWS_REGION=\"$SOURCE_REGION\" AWS_DEFAULT_REGION=\"$SOURCE_REGION\"",
            "SOURCE_URL=\"https://git-codecommit.$SOURCE_REGION.$AWS_DNS_SUFFIX/v1/repos/$SOURCE_REPOSITORY\"",
            "TARGET_URL=\"https://git-codecommit.$TARGET_REGION.$AWS_DNS_SUFFIX/v1/repos/$TARGET_REPOSITORY\"",
            "git clone --mirror \"$SOURCE_URL\" /tmp/source-mirror.git",
            "CREDENTIALS=\"$(aws sts assume-role --region \"$SOURCE_REGION\" --role-arn \"$TARGET_ROLE_ARN\" --role-session-name codecommit-replication --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)\"",
            "read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<< \"$CREDENTIALS\"",
            "unset CREDENTIALS",
            "export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN",
            "export AWS_REGION=\"$TARGET_REGION\" AWS_DEFAULT_REGION=\"$TARGET_REGION\"",
            "git --git-dir=/tmp/source-mirror.git push --mirror \"$TARGET_URL\"",
          ]
        }
      }
    })
  }

  # service_role references the role but not its permissions, and the log group must pre-exist so CodeBuild
  # never creates an unmanaged one (rules.md D-1).
  depends_on = [aws_iam_role_policy.build, aws_cloudwatch_log_group.build]
}

resource "aws_iam_role" "pipeline" {
  name_prefix = "${substr(var.project_name, 0, 20)}-pipeline-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "pipeline" {
  name = "CodeCommitReplicationPipeline"
  role = aws_iam_role.pipeline.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "UseArtifactBucket"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation", "s3:GetBucketVersioning", "s3:ListBucket"]
        Resource = aws_s3_bucket.artifacts.arn
      },
      {
        Sid      = "ReadAndWriteArtifacts"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },
      {
        Sid    = "ReadSourceRevision"
        Effect = "Allow"
        Action = [
          "codecommit:CancelUploadArchive",
          "codecommit:GetBranch",
          "codecommit:GetCommit",
          "codecommit:GetRepository",
          "codecommit:GetUploadArchiveStatus",
          "codecommit:UploadArchive",
        ]
        Resource = aws_codecommit_repository.source.arn
      },
      {
        Sid      = "RunMirrorBuild"
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
        Resource = aws_codebuild_project.mirror.arn
      },
    ]
  })

  depends_on = [aws_iam_role.pipeline]
}

# PutRolePolicy returning only proves the IAM write endpoint accepted the policy. The CodePipeline source
# action evaluates it through another endpoint, and a fresh apply reproduced a short window where
# GetRolePolicy and IAM simulation showed GetBranch as allowed while the action still reported that no
# identity-based policy allowed it. No AWS API exposes a propagation-ready signal, so a bounded wait is the
# only graph edge that prevents a new pipeline from starting in that window (rules.md D-1).
resource "time_sleep" "pipeline_role_propagation" {
  create_duration = "${var.pipeline_role_propagation_wait_seconds}s"

  # Re-run the wait if either the generated role or its permissions change. Merely depending on the policy
  # would not make an existing time_sleep wait again after an in-place policy update.
  triggers = {
    role_arn      = aws_iam_role.pipeline.arn
    policy_sha256 = sha256(aws_iam_role_policy.pipeline.policy)
  }

  depends_on = [aws_iam_role_policy.pipeline]
}

resource "aws_codepipeline" "replication" {
  name           = var.pipeline_name
  pipeline_type  = "V2"
  execution_mode = "QUEUED"
  role_arn       = aws_iam_role.pipeline.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artifacts.bucket
  }

  stage {
    name = "Source"

    action {
      name             = "SourceMain"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["SourceArtifact"]

      configuration = {
        RepositoryName       = aws_codecommit_repository.source.repository_name
        BranchName           = var.main_branch
        OutputArtifactFormat = "CODE_ZIP"
        PollForSourceChanges = "false"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name            = "MirrorRepository"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact"]

      configuration = {
        ProjectName = aws_codebuild_project.mirror.name
      }
      # There is intentionally no output_artifacts entry: the build changes only the target Git repository.
    }
  }

  # The initial commit prevents CreatePipeline's automatic first execution from seeing an empty repository.
  # The propagation wait includes the policy edge; retaining the bucket-control edges prevents that execution
  # from reaching a partially configured artifact bucket (rules.md D-1).
  depends_on = [
    terraform_data.source_initial_commit,
    time_sleep.pipeline_role_propagation,
    aws_s3_bucket_ownership_controls.artifacts,
    aws_s3_bucket_public_access_block.artifacts,
    aws_s3_bucket_server_side_encryption_configuration.artifacts,
  ]
}

resource "aws_iam_role" "events" {
  name_prefix = "${substr(var.project_name, 0, 20)}-events-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "events" {
  name = "StartReplicationPipeline"
  role = aws_iam_role.events.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["codepipeline:StartPipelineExecution"]
      Resource = local.pipeline_arn
    }]
  })

  depends_on = [aws_iam_role.events]
}

resource "aws_cloudwatch_event_rule" "source_main" {
  name        = var.event_rule_name
  description = "Starts ${var.pipeline_name} when ${var.main_branch} is created or updated"
  state       = "ENABLED"

  event_pattern = jsonencode({
    source        = ["aws.codecommit"]
    "detail-type" = ["CodeCommit Repository State Change"]
    resources     = [aws_codecommit_repository.source.arn]
    detail = {
      event         = ["referenceCreated", "referenceUpdated"]
      referenceType = ["branch"]
      referenceName = [var.main_branch]
    }
  })
}

resource "aws_cloudwatch_event_target" "pipeline" {
  rule      = aws_cloudwatch_event_rule.source_main.name
  target_id = "replication-pipeline"
  arn       = aws_codepipeline.replication.arn
  role_arn  = aws_iam_role.events.arn

  # role_arn does not imply that StartPipelineExecution is already attached (rules.md D-1).
  depends_on = [aws_iam_role_policy.events]
}
