locals {
  # The pipeline's own ARN, assembled from its name rather than read from the resource below.
  #
  # That is forced rather than preferred: the role's policy names the pipeline, the pipeline names the
  # role, and reading aws_codepipeline.code_pipeline.arn here would close that into a cycle Terraform
  # refuses to plan. The _monolithic template did the same thing for the same reason, and the cost is
  # the same too - the ARN is correct only because var.name is also what the resource below is called,
  # which is why the name is a variable read twice rather than a literal written twice (rules.md B-5).
  pipeline_arn = "arn:${var.partition}:codepipeline:${var.region}:${var.account_id}:${var.name}"

  # The deployment configuration is an AWS-owned one, so its ARN is assembled rather than referenced.
  deployment_config_arn = "arn:${var.partition}:codedeploy:${var.region}:${var.account_id}:deploymentconfig:${var.deployment_config_name}"
}
resource "aws_iam_role" "code_pipeline_iam_role" {
  # A generated name, where the _monolithic template used "CodePipelineRole-${local.stack_suffix}".
  name_prefix = var.role_name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["codepipeline.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
# Most of the _monolithic template's version of this policy was already scoped, which is unusual and
# worth saying: five of its six statements named the pipeline, the build project, the deployment group,
# the deployment configuration and the application individually. The sixth was "s3:*" on "*", and that
# one statement carried more than the other five put together - read and write and delete on every
# object in every bucket in the account, from a role trusted by a public AWS service.
#
# Here it is two buckets and the actions each one needs, which are not the same actions: the source
# bucket is read-only to the pipeline and the artifact store is read-write (rules.md A-5).
resource "aws_iam_role_policy" "code_pipeline_iam_role" {
  count = var.create_pipeline_policy ? 1 : 0

  name = "code-pipeline"
  role = aws_iam_role.code_pipeline_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid    = "ReadTheSourceArchive"
        Effect = "Allow"
        # GetBucketVersioning as well, on the bucket itself: an S3 source action checks that versioning
        # is enabled before it will track an object version, and without this the source stage fails
        # with an access denied that names the bucket rather than the missing action.
        Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:GetBucketVersioning"]
        Resource = [
          var.source_bucket_arn,
          "${var.source_bucket_arn}/*",
        ]
      },
      {
        Sid    = "ReadAndWriteArtifacts"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"]
        Resource = [
          var.artifact_bucket_arn,
          "${var.artifact_bucket_arn}/*",
        ]
      },
      {
        Sid      = "RunTheBuild"
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
        Resource = [var.code_build_project_arn]
      },
      {
        Sid    = "CreateTheDeployment"
        Effect = "Allow"
        Action = ["codedeploy:CreateDeployment", "codedeploy:GetDeployment"]
        Resource = [
          "arn:${var.partition}:codedeploy:${var.region}:${var.account_id}:deploymentgroup:${var.code_deploy_application_name}/${var.code_deploy_deployment_group_name}",
        ]
      },
      {
        Sid      = "ReadTheDeploymentConfiguration"
        Effect   = "Allow"
        Action   = ["codedeploy:GetDeploymentConfig"]
        Resource = [local.deployment_config_arn]
      },
      {
        Sid    = "RegisterTheRevision"
        Effect = "Allow"
        # GetApplication is added to the template's two. AWS's own documented CodePipeline service role
        # policy includes it for a CodeDeploy action, and the symptom of leaving it out is a deploy
        # stage that fails on its first call rather than on the deployment itself.
        Action = ["codedeploy:RegisterApplicationRevision", "codedeploy:GetApplicationRevision", "codedeploy:GetApplication"]
        Resource = [
          "arn:${var.partition}:codedeploy:${var.region}:${var.account_id}:application:${var.code_deploy_application_name}",
        ]
      },
      ],
      # The template granted the pipeline role StartPipelineExecution on its own pipeline. A pipeline
      # does not need to start itself - the EventBridge rule's role is what does that - so this is off
      # by default and kept available rather than deleted, because a manual release from the console
      # under this role would need it.
      var.allow_self_start ? [{
        Sid      = "StartThisPipeline"
        Effect   = "Allow"
        Action   = ["codepipeline:StartPipelineExecution"]
        Resource = [local.pipeline_arn]
      }] : [],
    )
  })
}
resource "aws_codepipeline" "code_pipeline" {
  name          = var.name
  pipeline_type = var.pipeline_type
  role_arn      = aws_iam_role.code_pipeline_iam_role.arn
  artifact_store {
    type     = "S3"
    location = var.artifact_bucket_name
  }
  stage {
    name = "SourceStage"
    action {
      name     = "SourceAction"
      category = "Source"
      owner    = "AWS"
      provider = "S3"
      version  = "1"
      configuration = {
        S3Bucket    = var.source_bucket_name
        S3ObjectKey = var.source_object_key
        # False, as the _monolithic template had it, and the EventBridge rule is what replaces it. Left
        # at its default of true the pipeline would get both mechanisms at once: an upload would start
        # a run through the rule, and the pipeline would also poll this object once a minute forever.
        # Setting it false is also what makes the trail and the rule load-bearing rather than optional.
        PollForSourceChanges = "false"
      }
      output_artifacts = ["SourceOutput"]
    }
  }
  stage {
    name = "BuildStage"
    action {
      name     = "BuildAction"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"
      configuration = {
        ProjectName = var.code_build_project_name
      }
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]
    }
  }
  # The deploy action, and the one place in this project where the _monolithic template made a choice
  # that is worth flagging rather than correcting.
  #
  # The documented action for an ECS blue/green deployment is CodeDeployToECS, which takes a taskdef
  # template and an appspec template as separate artefact files and substitutes the image into them.
  # This is the plain CodeDeploy action, which hands the input artefact to CreateDeployment as an S3
  # revision and is documented for EC2 and on-premises deployments.
  #
  # It is reproduced rather than changed because the build is built around it: post_build registers the
  # task definition revision itself and emits an appspec.json that already names that revision's ARN,
  # so the artefact needs no substitution and there is nothing for CodeDeployToECS's template handling
  # to do. Switching the action would mean rewriting the build to emit a taskdef.json with an
  # IMAGE1_NAME placeholder and dropping its register-task-definition call - a different design, not a
  # bug fix. This is the "min deployment" the project's own notes mention.
  #
  # What it means for a reader: if the deploy stage fails with the revision being rejected rather than
  # with a CodeDeploy error about the deployment itself, this is the line to look at first, and
  # CodeDeployToECS with a reworked buildspec is the alternative.
  stage {
    name = "DeployStage"
    action {
      name     = "DeployAction"
      category = "Deploy"
      owner    = "AWS"
      provider = "CodeDeploy"
      version  = "1"
      configuration = {
        ApplicationName = var.code_deploy_application_name
        # The deployment group's declared name. The template wrote the deployment group resource's id
        # here, and that id is CodeDeploy's generated group id rather than the name - which every
        # Terraform check accepts and the stage then fails on.
        DeploymentGroupName = var.code_deploy_deployment_group_name
      }
      input_artifacts = ["BuildOutput"]
    }
  }

  # The role has to carry its policy before the pipeline runs, and role_arn references the role rather
  # than the policy on it. CodePipeline starts an execution as soon as the pipeline is created, so this
  # is not a theoretical race - the first execution happens during apply (rules.md D-1).
  depends_on = [aws_iam_role_policy.code_pipeline_iam_role]
}
