resource "aws_iam_role" "code_build_iam_role" {
  # A generated name, where the _monolithic template used "CodeBuildRole-${local.stack_suffix}" and
  # needed a random_uuid sliced out of a synthetic CloudFormation stack ARN to make it unique.
  name_prefix = var.role_name_prefix
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
# The _monolithic template's version of this was one statement: every action the build makes plus
# "ecs:*" and "iam:PassRole", all on Resource "*". That is rules.md A-5's second case - the breadth was
# the template's own choice rather than something hidden in a script outside it - so the narrowing is a
# change to what the original did and the reasoning belongs here.
#
# ecs:* on * was the widest part of it and the least necessary: the build makes exactly one ECS call,
# RegisterTaskDefinition. Granted as ecs:* it also carried UpdateService and DeleteService on every
# service in the account, which matters more than usual in this project because a service here is
# already under a second controller's management - a stray UpdateService is how a blue/green deployment
# ends up half applied.
#
# iam:PassRole on * was the other one. The build passes one role, the task execution role, and
# unscoped PassRole on * means this build can hand any role in the account to any service that accepts
# one - which is a privilege escalation path rather than a permissions mistake.
#
# Four actions still have to be on *, and each is on * because IAM does not support a resource for it
# rather than because scoping it was skipped. They are called out in the statements below.
resource "aws_iam_role_policy" "code_build_iam_role" {
  count = var.create_build_policy ? 1 : 0

  name = "code-build"
  role = aws_iam_role.code_build_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteBuildLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        # The project's own log group, which CodeBuild names after the project. Scoped rather than *,
        # which also means a build cannot write into another project's log group.
        Resource = [
          "arn:${var.partition}:logs:${var.region}:${var.account_id}:log-group:/aws/codebuild/${var.name}",
          "arn:${var.partition}:logs:${var.region}:${var.account_id}:log-group:/aws/codebuild/${var.name}:*",
        ]
      },
      {
        Sid    = "ReadAndWritePipelineArtifacts"
        Effect = "Allow"
        # GetObjectVersion as well as GetObject: CodePipeline hands an artefact over by version, so a
        # build that can read the key but not a specific version of it fails on the input artefact with
        # an access denied that names the bucket rather than the permission.
        Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketAcl", "s3:GetBucketLocation"]
        Resource = [
          var.artifact_bucket_arn,
          "${var.artifact_bucket_arn}/*",
        ]
      },
      {
        Sid    = "AuthenticateToRegistry"
        Effect = "Allow"
        # On * because IAM has no resource for it: GetAuthorizationToken is an account-level call. Kept
        # in its own statement so that merging it with the one below cannot silently widen the push
        # actions to every repository in the account.
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "PushAndInspectImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          # DescribeImages is what post_build reads the tag it just pushed back out of, to build the
          # image reference for the task definition.
          "ecr:DescribeImages",
        ]
        Resource = [var.ecr_repository_arn]
      },
      {
        Sid    = "RegisterTaskDefinitionRevision"
        Effect = "Allow"
        # Also on * because IAM does not support a resource for either: a task definition family is not
        # addressable until a revision of it exists, so RegisterTaskDefinition has nothing to scope to.
        # This is two actions rather than the template's ecs:*.
        Action   = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"]
        Resource = "*"
      },
      {
        Sid    = "PassTaskExecutionRole"
        Effect = "Allow"
        # One role rather than *, and with the service condition as well. Registering a task definition
        # that names an execution role is a PassRole, so without this the register call fails - but
        # unscoped it is the escalation path described above.
        Action   = ["iam:PassRole"]
        Resource = [var.task_execution_role_arn]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      },
    ]
  })
}
locals {
  # The buildspec, reproduced from the _monolithic template with four corrections. Each one is marked
  # where it appears; collected here because they are the difference between this pipeline deploying
  # and failing partway.
  #
  # What the build does is worth stating, because it is not the usual CodeDeploy-to-ECS shape. It builds
  # an image, pushes it, registers a task definition revision itself, and emits an appspec that already
  # names that revision's ARN. So the artefact handed to the deploy stage is one complete file with no
  # placeholders in it - which is what the project's own notes mean by "min deployment" - rather than
  # the taskdef.json plus appspec template pair that the CodeDeployToECS action substitutes an image
  # into. See the aws_codepipeline resource for what that implies about the deploy action.
  #
  # The template also carried a commented-out block here that wrote main.go inside the build. It is
  # dropped rather than carried forward: the Go file arrives in the source archive the bastion uploaded,
  # which is the whole reason there is a source bucket.
  buildspec = <<-EOT
    version: 0.2
    env:
      variables:
        AWS_DEFAULT_REGION: ${var.region}
        AWS_ACCOUNT_ID: ${var.account_id}
        IMAGE_REPO_NAME: ${var.ecr_repository_name}
        CAPACITY_PROVIDER: ${var.capacity_provider_name}
        EXECUTION_ROLE_ARN: ${var.task_execution_role_arn}
        FAMILY: ${var.task_family}
        CONTAINER_NAME: ${var.container_name}
        CONTAINER_PORT: "${var.container_port}"
        LOG_GROUP_NAME: ${var.log_group_name}
    phases:
      pre_build:
        commands:
          - ln -sf /usr/share/zoneinfo/${var.timezone} /etc/localtime
          # The build's own Dockerfile, and the difference from the bastion's is deliberate: COPY . .
          # rather than COPY main.go ., because what is in this directory is the unpacked source
          # archive. This is also why the archive contains only main.go - a Dockerfile shipped inside
          # it would be overwritten by this line before it was ever used.
          - |
            echo 'FROM ${var.go_base_image}
            WORKDIR /app
            COPY . .
            RUN go build main.go
            EXPOSE ${var.container_port}
            CMD ["./main"]' > Dockerfile
      build:
        commands:
          # The template wrote this as "LC_TIME=ko_KR.UTF-8 date +'...'". The LC_TIME is dropped
          # because the format string has no locale-dependent field in it - no weekday, no month name -
          # so the variable changed nothing, and ko_KR.UTF-8 is not generated in the standard build
          # image anyway. The symlink in pre_build is what actually sets the clock these timestamps
          # come from.
          - IMAGE_VERSION=$(date +'%Y-%m-%d.%H.%M.%S')
          - IMAGE_TAG=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_VERSION
          # The base image comes from Docker Hub, which rate limits anonymous pulls by source address -
          # and every build here leaves through the same NAT gateways. A build that fails with
          # "toomanyrequests" is that limit and not a configuration problem; the answers are a Docker
          # Hub login added to this phase, or mirroring the base image into the ECR repository.
          - docker build -t $IMAGE_TAG .
          - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
          - docker push $IMAGE_TAG
      post_build:
        commands:
          - IMAGE_VERSION=$(echo $(aws ecr describe-images --repository-name $IMAGE_REPO_NAME --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags[0]') | tr -d '"')
          - CONTAINER_IMAGE="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_VERSION"
          - |
            jq -n --arg FAMILY $FAMILY --arg EXECUTION_ROLE_ARN $EXECUTION_ROLE_ARN --arg CONTAINER_NAME $CONTAINER_NAME --arg CONTAINER_IMAGE $CONTAINER_IMAGE --arg AWS_DEFAULT_REGION $AWS_DEFAULT_REGION --arg LOG_GROUP_NAME $LOG_GROUP_NAME --argjson CONTAINER_PORT $CONTAINER_PORT \
              '{ "family":$FAMILY, "executionRoleArn":$EXECUTION_ROLE_ARN, "networkMode":"awsvpc", "cpu":"${var.task_cpu}", "memory":"${var.task_memory}", "containerDefinitions":[{"healthCheck":{"command":["CMD-SHELL","curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"],"interval":${var.container_health_check_interval},"timeout":${var.container_health_check_timeout},"retries":${var.container_health_check_retries},"startPeriod":${var.container_health_check_start_period}},"logConfiguration":{"logDriver":"awslogs","options":{"awslogs-group":$LOG_GROUP_NAME,"awslogs-region":$AWS_DEFAULT_REGION,"awslogs-stream-prefix":"${var.log_stream_prefix}"}},"name":$CONTAINER_NAME,"image":$CONTAINER_IMAGE,"portMappings":[{"containerPort":$CONTAINER_PORT,"hostPort":$CONTAINER_PORT,"protocol":"tcp"}]}] }' \
              > task-definition.json
          - TASK_DEFINITION_JSON=$(aws ecs register-task-definition --cli-input-json file://task-definition.json)
          - TASK_DEFINITION_ARN=$(echo $TASK_DEFINITION_JSON | jq -r '.taskDefinition .taskDefinitionArn')
          # --argjson for the port rather than --arg, which is the second correction. --arg makes a JSON
          # string, so the appspec said "ContainerPort": "80" where the AppSpec reference documents an
          # integer, and ECS reads ContainerPort out of LoadBalancerInfo when CodeDeploy creates the
          # replacement task set.
          #
          # CAPACITY_PROVIDER is the third correction, made above where the variable is set: the
          # template passed the capacity provider resource's id into it, and that id is its ARN, while
          # CreateTaskSet documents capacityProviderStrategy.capacityProvider as the short name. An ARN
          # there is rejected, and the rejection arrives inside a CodeDeploy deployment rather than in
          # the build - so the pipeline reports a green build and a failed deploy.
          - >
            jq -n --arg TASK_DEFINITION_ARN $TASK_DEFINITION_ARN --arg CONTAINER_NAME $CONTAINER_NAME --argjson CONTAINER_PORT $CONTAINER_PORT --arg CAPACITY_PROVIDER $CAPACITY_PROVIDER
            '{"version": 0.0, "Resources": [{"TargetService": {"Type": "AWS::ECS::Service", "Properties": {"TaskDefinition": $TASK_DEFINITION_ARN, "LoadBalancerInfo": {"ContainerName": $CONTAINER_NAME, "ContainerPort": $CONTAINER_PORT}, "CapacityProviderStrategy": [{"Base":0,"CapacityProvider":$CAPACITY_PROVIDER,"Weight":1}]}}}]}'
            > appspec.json
    artifacts:
      files:
        - appspec.json
      discard-paths: yes
    EOT
}
resource "aws_codebuild_project" "code_build" {
  name = var.name
  # The ARN, not the name. The _monolithic template wrote the role's name here:
  #
  #   service_role = aws_iam_role.code_build_iam_role.name
  #
  # and this is the fourth correction. Both CreateProject and the provider document this field as the
  # role's ARN, and a bare name is not one - the attribute is a string either way, so terraform validate
  # and plan both pass and the failure is an InvalidInputException about the service role during apply.
  service_role  = aws_iam_role.code_build_iam_role.arn
  build_timeout = var.build_timeout
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    type         = var.environment_type
    compute_type = var.compute_type
    image        = var.environment_image
    # Required, and the _monolithic template did not set it - which is the fifth correction and the one
    # that stopped the build outright.
    #
    # privilegedMode defaults to false, and that is what runs a Docker daemon inside the build
    # container. Without it the three docker commands in the build phase have no daemon to talk to and
    # fail with "Cannot connect to the Docker daemon at unix:///var/run/docker.sock" - on a project
    # whose entire purpose is building an image. Nothing in the pipeline or the deployment group hints
    # at it; the symptom is a failed build stage and the reason is only in the build log.
    privileged_mode = var.privileged_mode
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = local.buildspec
  }

  # The role has to carry its policy before a build runs, and service_role references the role rather
  # than the policy on it. A build that starts first fails on its first AWS call, which CodePipeline
  # reports as a failed build stage (rules.md D-1).
  depends_on = [aws_iam_role_policy.code_build_iam_role]
}
