data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
locals {
  pipeline_arn = "arn:aws:codepipeline:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${var.name}-pipeline"
  # The namespace the image build stage publishes its output variables under. Only meaningful when that
  # stage exists, and the build stage below reads the digest of the image it just pushed from it.
  image_build_namespace = "ImageVariables"
  # The image the rendered Deployment runs, which is the one value neither Terraform nor the buildspec can
  # know: it is whatever this execution produced. Both forms are digest-pinned rather than tag-pinned.
  #
  #   with an image build stage - the sha256 digest that stage exports as ECRImageDigestId
  #   without one           - the ECR source's own ImageURI, which is already digest-pinned
  #
  # Keying off include_image_build_stage rather than off the source provider's name, because it is the
  # presence of that stage that decides which variable exists.
  image_uri = (var.include_image_build_stage
    ? "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/${var.ecr_repository_name}@#{${local.image_build_namespace}.ECRImageDigestId}"
    : "#{${var.source_action.namespace}.ImageURI}"
  )
  # The Deployment and Service the build stage writes out and the deploy stage applies.
  #
  # Built as typed objects and serialised, rather than assembled as an indented string inside a shell
  # heredoc inside a buildspec inside a Terraform heredoc - which is what the _monolithic template did,
  # four levels of quoting deep, with Terraform interpolations at the bottom. A wrong indent there was a
  # build failure on the pipeline's first run; here it is not expressible (rules.md E-3).
  #
  # Two values are deliberately left as shell variables for CodeBuild to substitute: the image URI, which
  # only the source stage knows, and the build and execution identifiers, which only exist at run time.
  # They are the reason this is rendered by the build stage at all rather than applied from Terraform.
  deployment_manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name = var.workload_name
      labels = {
        # Which build and which pipeline execution produced the running Deployment. This is the only
        # record of that, and it is worth having: a cluster whose pods do not match the last successful
        # execution is the question this answers.
        codebuild    = "$BUILD_ID"
        codepipeline = "$EXECUTION_ID"
      }
    }
    spec = {
      replicas = var.workload_replicas
      selector = {
        matchLabels = { "app.kubernetes.io/name" = var.workload_name }
      }
      template = {
        metadata = {
          labels = { "app.kubernetes.io/name" = var.workload_name }
        }
        spec = {
          containers = [{
            name  = var.workload_name
            image = "$ECR_IMAGE_URI"
            # Always, because the tag does not move in the manifest - the image behind "latest" does. With
            # IfNotPresent a node that already has that tag keeps running the old image and the deploy
            # succeeds with nothing changed.
            imagePullPolicy = "Always"
            ports = [{
              name          = "http"
              containerPort = var.workload_container_port
            }]
          }]
        }
      }
    }
  }
  service_manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name        = var.workload_name
      annotations = var.service_annotations
    }
    spec = {
      type     = "LoadBalancer"
      selector = { "app.kubernetes.io/name" = var.workload_name }
      ports = [{
        port       = var.workload_service_port
        targetPort = var.workload_container_port
        protocol   = "TCP"
      }]
    }
  }
  manifest_file_name = "system.yaml"
  rendered_manifest  = join("\n---\n", [yamlencode(local.deployment_manifest), yamlencode(local.service_manifest)])
  # What the image build stage needs, kept out of the policy so it can be included by a filter rather than by
  # a conditional whose branches would have different tuple lengths.
  image_build_policy_statements = [
    {
      # GetAuthorizationToken is account-wide by definition: it returns the registry's login token, and there
      # is no narrower resource for it.
      Effect   = "Allow"
      Action   = ["ecr:GetAuthorizationToken"]
      Resource = "*"
    },
    {
      # AWS documents DescribeRepositories on "*". It is scoped here instead, because the stage describes the
      # one repository it was configured with - a resource condition on this action filters which
      # repositories are returned rather than forbidding the call.
      Effect   = "Allow"
      Action   = ["ecr:DescribeRepositories"]
      Resource = [var.ecr_repository_arn]
    },
    # Not included: ecr-public:* and sts:GetServiceBearerToken, which AWS's own policy for this action lists.
    # They are the ECR Public path, and RegistryType below is private - GetServiceBearerToken exists to make
    # the ecr-public statement work. Switching RegistryType to public means adding both back.
    {
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
  ]
  buildspec = yamlencode({
    version = "0.2"
    env = {
      variables = {
        AWS_ACCOUNT_ID  = data.aws_caller_identity.current.account_id
        IMAGE_REPO_NAME = var.ecr_repository_name
      }
    }
    phases = {
      build = {
        commands = [
          # The pipeline execution id arrives as an environment variable set by the stage; the build id is
          # CodeBuild's own and has to be trimmed to its short form.
          "BUILD_ID=$(echo $CODEBUILD_BUILD_ID | cut -d':' -f2)",
          # A quoted heredoc would stop the two variables above from being substituted, which is the one
          # thing this step exists to do - so the delimiter is deliberately unquoted, and the manifest is
          # generated by Terraform so that nothing else in it can be mistaken for a shell expansion.
          "cat > ${local.manifest_file_name} << MANIFEST\n${local.rendered_manifest}\nMANIFEST",
          # Printed so the rendered manifest is in the build log. Without it, a deploy stage that fails on
          # a malformed manifest gives no way to see what was actually produced.
          "cat ${local.manifest_file_name}",
        ]
      }
    }
    artifacts = {
      files = [local.manifest_file_name]
      # Without this the file arrives in the artifact under its build directory path and the deploy
      # stage's ManifestFiles setting, which names a bare file name, does not find it.
      "discard-paths" = "yes"
    }
  })
}
# The artifact store. The _monolithic template declared "resource aws_s3_bucket ... {}" - no versioning,
# no encryption, no public access block, no lifecycle rule - for a bucket a pipeline writes to on every
# run.
resource "aws_s3_bucket" "artifacts" {
  bucket        = var.artifact_bucket_name
  bucket_prefix = var.artifact_bucket_name == null ? "${var.name}-artifacts-" : null
  # True, because every pipeline run leaves objects here and a destroy would otherwise stop at
  # BucketNotEmpty with the cluster already gone.
  force_destroy = true
}
# CodePipeline reads and writes object versions - the role policy grants s3:GetObjectVersion - so the
# bucket has to have versioning on. Without it the pipeline still works and the permission is meaningless,
# which is the kind of mismatch that only shows up when something goes wrong.
resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# With versioning on and a pipeline running repeatedly, every artifact version is kept forever unless
# something removes it. This is the rule the original had no place for.
resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-old-artifact-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.artifacts]
}
# ---------------------------------------------------------------------------------------------------
# The build project: renders the manifest and nothing else.
# ---------------------------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "build" {
  name              = "/aws/codebuild/${var.name}-build"
  retention_in_days = var.log_retention_days
}
resource "aws_iam_role" "codebuild" {
  name_prefix = "${substr(var.name, 0, 24)}-build-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
# The _monolithic template created this role and attached nothing to it at all, so the build stage could
# not write a log line or read its own source artifact - the pipeline would have failed on its first run.
resource "aws_iam_role_policy" "codebuild" {
  name = "build"
  role = aws_iam_role.codebuild.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
        # Scoped to this project's own log group rather than to every group in the account.
        Resource = ["${aws_cloudwatch_log_group.build.arn}:*"]
      },
      {
        # The source artifact in, the build artifact out.
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = ["${aws_s3_bucket.artifacts.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation", "s3:ListBucket"]
        Resource = [aws_s3_bucket.artifacts.arn]
      },
    ]
  })
}
resource "aws_codebuild_project" "build" {
  name          = "${var.name}-build"
  description   = "Renders the Kubernetes manifest the deploy stage applies"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = var.build_timeout_minutes

  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type = var.codebuild_compute_type
    type         = "LINUX_CONTAINER"
    image        = var.codebuild_image
  }
  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build.name
    }
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = local.buildspec
  }

  # service_role is an ARN reference, which orders this after the role but not after its policy
  # (rules.md D-1). A build that starts before the policy lands fails on its first log write.
  depends_on = [aws_iam_role_policy.codebuild]
}
# ---------------------------------------------------------------------------------------------------
# The pipeline.
# ---------------------------------------------------------------------------------------------------
resource "aws_iam_role" "pipeline" {
  name_prefix = "${substr(var.name, 0, 24)}-pipe-"

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
  name = "pipeline"
  role = aws_iam_role.pipeline.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect   = "Allow"
          Action   = ["s3:GetBucketVersioning", "s3:GetBucketAcl", "s3:GetBucketLocation"]
          Resource = [aws_s3_bucket.artifacts.arn]
        },
        {
          Effect   = "Allow"
          Action   = ["s3:PutObject", "s3:GetObject", "s3:GetObjectVersion"]
          Resource = ["${aws_s3_bucket.artifacts.arn}/*"]
        },
        {
          Effect   = "Allow"
          Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codepipeline/${var.name}-pipeline:*"]
        },
        {
          Effect   = "Allow"
          Action   = ["codebuild:BatchGetBuilds", "codebuild:StartBuild"]
          Resource = [aws_codebuild_project.build.arn]
        },
        {
          Effect   = "Allow"
          Action   = "eks:DescribeCluster"
          Resource = var.cluster_arn
        },
        {
          # The deploy stage runs inside the VPC, which means CodePipeline creates an elastic network
          # interface in the subnets given below. These are the permissions for that, and they are
          # resource-less by nature: the interface does not exist until the stage creates it.
          Effect = "Allow"
          Action = [
            "ec2:DescribeDhcpOptions",
            "ec2:DescribeNetworkInterfaces",
            "ec2:DescribeRouteTables",
            "ec2:DescribeSubnets",
            "ec2:DescribeSecurityGroups",
            "ec2:DescribeVpcs",
            "ec2:CreateNetworkInterface",
            "ec2:CreateNetworkInterfacePermission",
            "ec2:DeleteNetworkInterface",
          ]
          Resource = "*"
        },
      ],
      # Whatever the source stage needs. Supplied by the caller, because only the caller knows which of
      # the three sources it configured (rules.md B-6).
      var.source_role_policy_statements,
      # The image build stage pushes into the repository, which the ECR-source variant does not do at all.
      #
      # Written as a filtered for-expression rather than a conditional. A conditional's two branches have to
      # have the same type, and two tuples of different length do not - "The 'true' tuple has length 2, but
      # the 'false' tuple has length 0". The filter produces one list either way.
      [for statement in local.image_build_policy_statements : statement if var.include_image_build_stage],
    )
  })
}
resource "aws_codepipeline" "pipeline" {
  name = "${var.name}-pipeline"
  # V2, which is what the QUEUED execution mode and the pipeline-level variables need.
  pipeline_type = "V2"
  # QUEUED rather than SUPERSEDED: a second push waits for the first deploy to finish instead of
  # replacing it, so two deploys never race on the same cluster.
  execution_mode = var.execution_mode
  role_arn       = aws_iam_role.pipeline.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artifacts.id
  }

  stage {
    name = "Source"
    action {
      name      = var.source_action.name
      category  = "Source"
      owner     = "AWS"
      provider  = var.source_action.provider
      version   = "1"
      run_order = 1
      # Only the ECR source produces a variable a later stage reads. A namespace on a source that exports
      # nothing is harmless; a missing one on a source whose variable is referenced fails at execution.
      namespace        = var.source_action.namespace
      configuration    = var.source_action.configuration
      output_artifacts = ["SourceArtifact"]
    }
  }

  # Only for the sources that hand over a source tree rather than an image. The ECR variant skips it,
  # because the image already exists - pushing it is what started the pipeline (rules.md B-4).
  dynamic "stage" {
    for_each = var.include_image_build_stage ? [1] : []
    content {
      name = "ImageBuild"
      action {
        name      = "ImageBuildAction"
        category  = "Build"
        owner     = "AWS"
        provider  = "ECRBuildAndPublish"
        version   = "1"
        run_order = 1
        # Required, not decorative: the build stage reads this stage's ECRImageDigestId, and the action
        # publishes its variables only under a namespace. Without it the reference resolves to nothing at
        # execution time while the pipeline itself applies cleanly.
        namespace = local.image_build_namespace
        configuration = {
          ECRRepositoryName = var.ecr_repository_name
          RegistryType      = "private"
          ImageTags         = var.image_tags
        }
        input_artifacts = ["SourceArtifact"]
      }
    }
  }

  stage {
    name = "Build"
    action {
      name      = "ManifestBuildAction"
      category  = "Build"
      owner     = "AWS"
      provider  = "CodeBuild"
      version   = "1"
      run_order = 1
      configuration = {
        ProjectName   = aws_codebuild_project.build.name
        PrimarySource = "SourceArtifact"
        # The two values the build stage cannot know on its own: the image this execution produced, and the
        # execution's own identifier.
        EnvironmentVariables = jsonencode([
          {
            name  = "ECR_IMAGE_URI"
            type  = "PLAINTEXT"
            value = local.image_uri
          },
          {
            name  = "EXECUTION_ID"
            type  = "PLAINTEXT"
            value = "#{codepipeline.PipelineExecutionId}"
          },
        ])
      }
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["BuildArtifact"]
    }
  }

  stage {
    name = "Deploy"
    action {
      name      = "EksDeployAction"
      category  = "Deploy"
      owner     = "AWS"
      provider  = "EKS"
      version   = "1"
      run_order = 1
      configuration = {
        ClusterName   = var.cluster_name
        ManifestFiles = local.manifest_file_name
        Namespace     = var.workload_namespace
        # Comma-separated strings rather than lists: this is a stage configuration map, so every value is
        # a string whatever it represents.
        SecurityGroupIds = join(",", var.deploy_security_group_ids)
        Subnets          = join(",", var.deploy_subnet_ids)
      }
      input_artifacts = ["BuildArtifact"]
    }
  }

  # role_arn is an ARN reference, which orders this after the role but not after its policy
  # (rules.md D-1). A pipeline that starts before the policy lands fails on its source stage.
  depends_on = [aws_iam_role_policy.pipeline]
}
