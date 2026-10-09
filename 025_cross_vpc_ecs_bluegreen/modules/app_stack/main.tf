# One application stack: a task definition, an ECS service, the two target groups and two listener
# rules it needs, and the CodeDeploy plus CodePipeline machinery that performs its blue/green
# switch. The root instantiates this twice, for green and for red.
#
# Roughly a third of the _monolithic template was this written out twice under a green_ and a red_
# prefix - fourteen resources each, near-identical. Reading it meant diffing two resource bodies to
# find out what the two stacks actually differed by. That list turns out to be short, and it is now
# in one place: the app_stacks map in the root, and the variables below.
#
#   task_cpu                  green 1024, red 512
#   launch_type               green EC2, red FARGATE (which is also the only reason
#                             platform_version exists, and what requires_compatibilities is
#                             derived from below)
#   listener_rule_priority    green 1, red 2
#   health_check_rule_priority green 3, red 4
#   ecr encryption            green AES256, red the project KMS key (in modules/ecr_repository)
#
# And what they do not differ by, which is worth stating because the duplicated code made it look
# like they might: container port, task memory, image tag, desired count, health check path,
# deregistration delay, the FireLens sidecar, the secret references, the deployment configuration,
# the pipeline shape and both buckets. The path patterns and every name differ only by the stack
# key, so they are derived from it rather than passed in.
locals {
  # Derived rather than taken as a variable, so the invalid combination cannot be expressed
  # (rules.md B-1): a Fargate service whose task definition does not declare FARGATE compatibility
  # is rejected at CreateService, and an EC2 service whose task definition declares only FARGATE is
  # rejected the same way. The _monolithic template kept the two in agreement by hand.
  requires_compatibilities = var.launch_type == "FARGATE" ? ["FARGATE"] : ["EC2"]
  image                    = "${var.image_uri}:${var.image_tag}"
}
# The application log group.
#
# The _monolithic template declared no log group and relied on the FireLens cloudwatch plugin's
# auto_create_group to make it at runtime. That works, and it leaves a group behind after destroy
# with no retention, and it means the dashboard queries a group that does not exist until a task
# has logged something - a log widget against a missing group renders as an error rather than as an
# empty chart.
#
# auto_create_group stays set on the plugin as well: the plugin tolerates the group already
# existing, and leaving it on means a group deleted by hand mid-demo comes back.
resource "aws_cloudwatch_log_group" "app_log_group" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_in_days
  tags = {
    Name = var.log_group_name
  }
}
# Two target groups per stack, which is what CodeDeploy needs rather than a redundancy.
#
# A blue/green deployment holds one of them live while the replacement task set registers into the
# other, then rewrites the listener rule to point at it. Both have to exist up front and both have
# to be the same shape, so the only difference between these two resources is the name.
resource "aws_lb_target_group" "blue" {
  name        = var.target_group_blue_name
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id
  health_check {
    protocol            = "HTTP"
    path                = var.health_check_path
    port                = tostring(var.container_port)
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    matcher             = var.health_check_matcher
  }
  deregistration_delay = var.deregistration_delay
  tags = {
    Name = var.target_group_blue_name
  }
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_lb_target_group" "green" {
  name        = var.target_group_green_name
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id
  health_check {
    protocol            = "HTTP"
    path                = var.health_check_path
    port                = tostring(var.container_port)
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    matcher             = var.health_check_matcher
  }
  deregistration_delay = var.deregistration_delay
  tags = {
    Name = var.target_group_green_name
  }
  lifecycle {
    create_before_destroy = true
  }
}
# The rule that routes this stack's path prefix to it, and the one place in the project where
# CodeDeploy and Terraform both write to the same field.
#
# A blue/green deployment finishes by rewriting the production listener's forward action from the
# live target group to the other one - blue to green on the first deployment, which is the seed
# artefact's at pipeline creation. Terraform recorded blue, so the next plan proposes
# changing it back - and applying that plan moves live traffic to the task set CodeDeploy has
# already drained and terminated, which is a 503 for every request on this path until someone
# notices.
#
# ignore_changes on action is the equivalent here of rules.md E-8's ignore_fields: exclude the
# field the controller owns and keep tracking the rest. The granularity is coarser than E-8's
# because an aws_lb_listener_rule's whole forward configuration is one attribute - so priority and
# condition stay tracked and the target group does not. The alternative, ignoring the resource
# wholesale, would stop a path pattern change from ever being applied.
resource "aws_lb_listener_rule" "path" {
  listener_arn = var.listener_arn
  priority     = var.listener_rule_priority
  condition {
    path_pattern {
      # Both forms, as the _monolithic template had it: an ALB path pattern is not a prefix match,
      # so "/green" alone does not match "/green/" and vice versa.
      values = ["/${var.stack_key}", "/${var.stack_key}/"]
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  lifecycle {
    ignore_changes = [action]
  }
}
# The health check rule, reproduced from the _monolithic template, and worth a warning rather than
# a description.
#
# Both stacks declare a rule for the same path - the template used priority 3 for green and 4 for
# red, both matching exactly "/health" - and an ALB evaluates rules in priority order and stops at
# the first match. So the second one can never fire: a request to /health always reaches whichever
# stack holds the lower priority, and the other rule is dead configuration that still occupies a
# priority number.
#
# It is kept because removing it changes what the original did, and because the per-stack health
# check that actually matters is the target group's, which is evaluated by the load balancer
# against each task directly and does not go through a listener rule at all. If the intent was a
# per-stack health path, the fix is a distinct path per stack - "/health/${stack_key}" - not a
# different priority.
resource "aws_lb_listener_rule" "health_check" {
  listener_arn = var.listener_arn
  priority     = var.health_check_rule_priority
  condition {
    path_pattern {
      values = [var.health_check_path]
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  lifecycle {
    ignore_changes = [action]
  }
}
locals {
  # The container definitions, held here rather than inline in the task definition because two
  # things are built from them: the task definition Terraform registers, and the taskdef.json
  # template every pipeline artefact carries. One list means the template cannot drift from what
  # the service actually runs (rules.md B-5).
  #
  # camelCase keys, where the _monolithic template carried CloudFormation's PascalCase - Name,
  # Image, PortMappings, LogConfiguration. The ECS API tolerates both, because the SDK unmarshals
  # this JSON case-insensitively, so the template worked; camelCase is what RegisterTaskDefinition
  # documents and what the API returns, which is also what the provider compares against when it
  # decides whether this attribute has changed.
  container_definitions = [
    {
      name      = var.container_name
      image     = local.image
      essential = true
      healthCheck = {
        # Runs inside the container, so it needs curl present in the image - the Dockerfile the
        # build step writes installs it for exactly this. A container whose health check command
        # is missing reports unhealthy forever and ECS replaces it in a loop.
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
        interval    = var.container_health_check_interval
        retries     = var.container_health_check_retries
        startPeriod = var.container_health_check_start_period
        timeout     = var.container_health_check_timeout
      }
      portMappings = [{
        containerPort = var.container_port
        # Equal to containerPort because the network mode is awsvpc, where the task has its own
        # interface and there is no port translation. A different value is rejected at
        # RegisterTaskDefinition.
        hostPort = var.container_port
        name     = "http"
        protocol = "tcp"
      }]
      # Three keys out of one secret. The ARN suffix is "<key>::" - key, then an empty version
      # stage and an empty version id, which means the current version.
      secrets = [
        { name = "DB_URL", valueFrom = "${var.secret_arn}:DB_URL::" },
        { name = "DB_USER", valueFrom = "${var.secret_arn}:DB_USER::" },
        { name = "DB_PASSWD", valueFrom = "${var.secret_arn}:DB_PASSWD::" },
      ]
      logConfiguration = {
        # awsfirelens hands this container's stdout to the log_router container below rather than
        # to the awslogs driver, which is what makes the exclude-pattern possible: the health check
        # request fires every interval on every task, and without the filter it is most of the log.
        logDriver = "awsfirelens"
        options = {
          Name              = "cloudwatch"
          log_group_name    = aws_cloudwatch_log_group.app_log_group.name
          auto_create_group = "true"
          # $(ecs_task_id) is resolved by FireLens, not by Terraform - a "$(" is not an
          # interpolation, so it reaches the container as written.
          log_stream_name   = "${title(var.stack_key)}-$(ecs_task_id)"
          region            = var.region
          "exclude-pattern" = var.log_exclude_pattern
        }
      }
    },
    {
      name  = "log_router"
      image = var.fluent_bit_image
      # Essential, as the _monolithic template had it, which couples the two: a fluent-bit that
      # cannot start takes the application container down with it. That is the safer setting for a
      # demo whose point is partly the log widgets - the alternative is an application that serves
      # traffic while its logs silently go nowhere.
      essential = true
      user      = "0"
      firelensConfiguration = {
        type = "fluentbit"
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          # A shared group across both stacks, deliberately not a Terraform resource: it is one
          # name used by two instances of this module, so declaring it here would have the second
          # apply fail with ResourceAlreadyExistsException. awslogs-create-group makes the agent
          # create it, and the execution role policy grants logs:CreateLogGroup for that reason.
          "awslogs-group"         = var.fluent_bit_log_group_name
          "awslogs-region"        = var.region
          "awslogs-create-group"  = "true"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    },
  ]

  # The taskdef.json CodeDeployToECS reads from an artefact: the same registration request as the
  # resource below, with the application image replaced by the placeholder the pipeline fills in
  # from imageDetail.json. The workbench step used to produce this with ecs describe-task-definition
  # and a jq filter that deleted the response-only fields; building it from the same locals gets the
  # same document without a round trip.
  #
  # The two replace() calls undo jsonencode's HTML escaping. It writes < and > as \u003c and \u003e,
  # which is valid JSON for the same string - but the placeholder is meant to be found as the literal
  # text <IMAGE1_NAME>, and nothing documents that CodePipeline decodes the JSON before it looks.
  # Nothing else in this document contains either character.
  task_definition_template = replace(replace(jsonencode({
    family                  = var.task_definition_family
    taskRoleArn             = var.task_role_arn
    executionRoleArn        = var.execution_role_arn
    networkMode             = "awsvpc"
    requiresCompatibilities = local.requires_compatibilities
    cpu                     = var.task_cpu
    memory                  = var.task_memory
    runtimePlatform = {
      cpuArchitecture       = var.cpu_architecture
      operatingSystemFamily = "LINUX"
    }
    containerDefinitions = [
      for container in local.container_definitions :
      container.name == var.container_name ? merge(container, { image = "<${var.image_placeholder_name}>" }) : container
    ]
  }), "\\u003c", "<"), "\\u003e", ">")

  # The appspec, as the workbench step wrote it. <TASK_DEFINITION> is CodeDeployToECS's own
  # placeholder for the revision the pipeline registers from the template above.
  app_spec_template = <<-EOT
    version: 0.0
    Resources:
      - TargetService:
          Type: AWS::ECS::Service
          Properties:
            TaskDefinition: <TASK_DEFINITION>
            LoadBalancerInfo:
              ContainerName: ${var.container_name}
              ContainerPort: ${var.container_port}
    EOT
}
resource "aws_ecs_task_definition" "task_definition" {
  family                   = var.task_definition_family
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  network_mode             = "awsvpc"
  requires_compatibilities = local.requires_compatibilities
  task_role_arn            = var.task_role_arn
  execution_role_arn       = var.execution_role_arn
  runtime_platform {
    cpu_architecture        = var.cpu_architecture
    operating_system_family = "LINUX"
  }
  container_definitions = jsonencode(local.container_definitions)
}
resource "aws_ecs_service" "service" {
  name            = var.service_name
  cluster         = var.cluster_name
  task_definition = aws_ecs_task_definition.task_definition.arn
  desired_count   = var.desired_count
  launch_type     = var.launch_type
  # Only meaningful for Fargate, and rejected for EC2 - so it is null unless this stack is the
  # Fargate one.
  platform_version              = var.launch_type == "FARGATE" ? var.platform_version : null
  availability_zone_rebalancing = var.availability_zone_rebalancing
  # CODE_DEPLOY, which is what makes everything else in this module necessary: with the default ECS
  # controller there would be one target group and no CodeDeploy application at all. ECS validates
  # the shape at CreateService and requires exactly one load_balancer block naming the currently
  # live target group.
  deployment_controller {
    type = "CODE_DEPLOY"
  }
  network_configuration {
    assign_public_ip = false
    security_groups  = var.security_group_ids
    subnets          = var.subnet_ids
  }
  load_balancer {
    container_name   = var.container_name
    container_port   = var.container_port
    target_group_arn = aws_lb_target_group.blue.arn
  }

  lifecycle {
    # The two fields CodeDeploy owns once the first deployment has run.
    #
    # It registers a new task definition revision and moves the service to it, and it swaps the
    # target group in the service's load balancer configuration. Terraform recorded the revision
    # it created and the blue target group, so without this every plan after a deployment proposes
    # rolling the service back to them - and applying it would undo the deployment while
    # CodeDeploy still believes it succeeded.
    #
    # This is the same argument rules.md E-8 makes for a controller-owned field on a Kubernetes
    # object, with one difference that matters: there the advice is to exclude the single path
    # rather than the whole manifest, and here task_definition and load_balancer already are
    # single attributes, so naming them is as narrow as it gets. Everything else about the service
    # - desired count, subnets, security groups - stays tracked.
    #
    # platform_version belongs to the same list for a different reason. The service is created
    # with LATEST, ECS reports the version LATEST resolved to (1.4.0), and every plan then proposes
    # setting it back to LATEST - which UpdateService refuses for a CODE_DEPLOY service, because on
    # that controller the platform version changes only through a CodeDeploy deployment. Left
    # tracked, it fails every apply after the first. Null on the EC2 stack, so ignoring it there
    # changes nothing.
    ignore_changes = [task_definition, load_balancer, platform_version]
  }

  # Both listener rules before the service. The service does not reference them, and a service
  # created first is accepted and then has traffic arriving at a listener whose rules do not route
  # to it yet. The _monolithic template carried the same edge, and with both stacks' rules in it,
  # which a single-stack module cannot express (rules.md D-1).
  depends_on = [
    aws_lb_listener_rule.path,
    aws_lb_listener_rule.health_check,
  ]
}
# --- Delivery: CodeDeploy, CodePipeline and the EventBridge rule that starts it. ---
#
# The three IAM roles below are per stack, where the _monolithic template had one of each shared
# between both. That is a divergence and the reason is rules.md A-5: every one of these policies
# names resources only this stack has - its pipeline, its two buckets, its application and
# deployment group - so a shared role would need the union of two stacks' resources, which is a
# wildcard as soon as there are two of them. That is how the template's CodePipeline policy came
# to be "s3:*, codebuild:*, codedeploy:* on *".
#
# The task and execution roles are the opposite case and stay shared: their policies name the one
# secret and the one key both stacks use. See modules/ecs_task_iam_roles.
resource "aws_iam_role" "code_deploy_iam_role" {
  name_prefix = var.code_deploy_role_name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["codedeploy.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
# AWSCodeDeployRoleForECS stays as the _monolithic template attached it. This is rules.md A-5's
# other half: it is the AWS service-role policy documented for ECS blue/green, already scoped to
# the ECS, elbv2 and iam:PassRole calls CodeDeploy makes on a deployment. Replacing it with a
# hand-written policy would be guessing at that list, and guessing short produces a deployment
# that stops partway with the traffic already shifted.
resource "aws_iam_role_policy_attachment" "code_deploy_iam_role" {
  for_each   = toset(var.code_deploy_policy_arns)
  role       = aws_iam_role.code_deploy_iam_role.name
  policy_arn = each.value
}
resource "aws_codedeploy_app" "code_deploy_application" {
  name             = var.code_deploy_application_name
  compute_platform = "ECS"
}
resource "aws_codedeploy_deployment_group" "code_deploy_deployment_group" {
  app_name               = aws_codedeploy_app.code_deploy_application.name
  deployment_group_name  = var.code_deploy_deployment_group_name
  service_role_arn       = aws_iam_role.code_deploy_iam_role.arn
  deployment_config_name = var.deployment_config_name
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }
  ecs_service {
    cluster_name = var.cluster_name
    service_name = aws_ecs_service.service.name
  }
  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [var.listener_arn]
      }
      # Both target groups by name, not ARN, which is what CodeDeploy takes. Order is not
      # significant - CodeDeploy works out which one the service currently uses.
      target_group {
        name = aws_lb_target_group.blue.name
      }
      target_group {
        name = aws_lb_target_group.green.name
      }
    }
  }
  blue_green_deployment_config {
    deployment_ready_option {
      # CONTINUE_DEPLOYMENT, as the _monolithic template had it: traffic shifts as soon as the
      # replacement task set is healthy, with no manual approval step. STOP_DEPLOYMENT would park
      # the deployment waiting for someone, which is the production setting and the wrong one for
      # a demo that then has nothing to show.
      action_on_timeout = var.deployment_ready_action_on_timeout
    }
    terminate_blue_instances_on_deployment_success {
      action = "TERMINATE"
      # Zero, as the template had it. This is the window in which a rollback is instant, because
      # the original task set is still running - at zero there is no such window, and a rollback
      # has to start new tasks.
      termination_wait_time_in_minutes = var.termination_wait_time_in_minutes
    }
  }
  auto_rollback_configuration {
    enabled = true
    events  = var.auto_rollback_events
  }

  # The role must carry its policy before CodeDeploy validates it. service_role_arn orders this
  # after the role but not after the attachment, and CodeDeploy checks the role at
  # CreateDeploymentGroup - so a race here fails the apply rather than the first deployment
  # (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.code_deploy_iam_role]
}
# The source bucket. A pipeline run is started by dropping an artefact here, which is what the
# helper script the second SSM association writes does.
resource "aws_s3_bucket" "source_bucket" {
  # A generated name rather than the template's "ws25-cd-green-artifact-${var.random_number}",
  # which required a RandomNumber variable to be supplied by hand for no reason other than that S3
  # bucket names are globally unique. bucket_prefix is the provider's way of getting that, and it
  # removes the one variable in this project that had no default.
  bucket_prefix = var.source_bucket_prefix
  # force_destroy, which the _monolithic template did not set. Every pipeline run leaves an
  # artifact.zip and a version of it here, and S3 refuses to delete a bucket with objects in it -
  # so a destroy stops with BucketNotEmpty on both buckets of both stacks. Versioning is on, so
  # this deletes every version too, which makes the destroy irreversible.
  force_destroy = var.force_destroy
  tags = {
    Name = "${var.stack_key}-source"
  }
}
# Required, not optional: a CodePipeline S3 source action polls or is notified about a specific
# object version, and CreatePipeline rejects a source bucket without versioning enabled.
resource "aws_s3_bucket_versioning" "source_bucket_versioning" {
  bucket = aws_s3_bucket.source_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
# The artefact the pipeline's first execution reads.
#
# CodePipeline starts an execution the moment a pipeline is created - the CreatePipeline trigger -
# and there is no setting that turns it off. In the _monolithic design nothing was in the source
# bucket at that moment: the artefact is uploaded later, by a person running the helper script. So
# every pipeline failed its first execution about a second after it was created, with
#
#   The object with key 'artifact.zip' returned a Forbidden error.
#
# Forbidden rather than not-found, because S3 answers a GetObject for a missing key with 403 to a
# caller that cannot list the bucket. That is why the pipeline role now has s3:ListBucket as well:
# the same situation would read as a missing object rather than as a permission problem.
#
# The seed deploys the image the service already runs, image_tag, so the first execution is a
# complete blue/green deployment that changes nothing a request can see. The demo artefact the
# helper script uploads still carries deploy_image_version, and that is still the switch.
#
# The zip lands in build/ as a side effect of reading this, one file per stack.
data "archive_file" "seed_artifact" {
  type        = "zip"
  output_path = "${path.module}/build/${var.stack_key}-${var.source_object_key}"
  source {
    content  = local.task_definition_template
    filename = var.task_definition_template_path
  }
  source {
    content  = local.app_spec_template
    filename = var.app_spec_template_path
  }
  source {
    content  = jsonencode({ ImageURI = local.image })
    filename = var.image_detail_file_name
  }
}
resource "aws_s3_object" "seed_artifact" {
  bucket      = aws_s3_bucket.source_bucket.id
  key         = var.source_object_key
  source      = data.archive_file.seed_artifact.output_path
  source_hash = data.archive_file.seed_artifact.output_base64sha256

  # The object belongs to the helper script from the second upload onward, and every upload is a
  # new version under the same key. Without ignore_changes, the next plan that sees a different
  # seed - an image_tag change, or simply the archive being re-read after a dependency changed -
  # would upload it again, and that upload is a deployment: it would roll the service back from
  # whatever the demo deployed. The seed has one job, and it is done once the first execution has
  # read it (rules.md E-8, the second row of its table).
  lifecycle {
    ignore_changes = all
  }

  # The pipeline reads a specific object version, so the bucket has to be versioned before the
  # seed is written. An object written before versioning is enabled carries the null version.
  #
  # The role policy because of a pipeline that already exists. Once the trail and the EventBridge
  # rule are in place, writing this object is itself what starts an execution, so the role that
  # execution runs as has to carry its permissions by then.
  depends_on = [
    aws_s3_bucket_versioning.source_bucket_versioning,
    aws_iam_role_policy.code_pipeline_iam_role,
  ]
}
# The pipeline's own artifact store, which is separate from the source bucket: the source action
# reads from one and writes its output artefact into the other.
resource "aws_s3_bucket" "artifact_store_bucket" {
  bucket_prefix = var.artifact_store_bucket_prefix
  force_destroy = var.force_destroy
  tags = {
    Name = "${var.stack_key}-artifact-store"
  }
}
resource "aws_iam_role" "code_pipeline_iam_role" {
  name_prefix = var.code_pipeline_role_name_prefix
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
# The _monolithic template's version of this was one statement:
#
#   Action = ["codepipeline:StartPipelineExecution", "s3:*", "codebuild:*", "codedeploy:*",
#             "ecs:RegisterTaskDefinition", "iam:PassRole"]
#   Resource = "*"
#
# Four things are wrong with it beyond the wildcard, and they are worth naming because they are
# what narrowing it reveals (rules.md A-5, second case - the template attached this in Terraform):
#
#   codebuild:*                      this pipeline has no build stage. Source then Deploy, nothing
#                                    else. The permission is for a stage that does not exist.
#   codepipeline:StartPipelineExecution  the pipeline does not start itself; the EventBridge rule
#                                    below does, with its own role. This grants the pipeline the
#                                    ability to start every pipeline in the account.
#   s3:*                             includes DeleteBucket on every bucket in the account.
#   iam:PassRole on *                the one that matters. A registered task definition names a
#                                    task role and an execution role, so the pipeline must pass
#                                    them - unscoped, that is the ability to pass any role in the
#                                    account to any service, which is a privilege escalation
#                                    rather than a permission.
resource "aws_iam_role_policy" "code_pipeline_iam_role" {
  name = "CodePipelinePolicy"
  role = aws_iam_role.code_pipeline_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:GetBucketVersioning", "s3:GetBucketLocation"]
        Resource = [
          aws_s3_bucket.source_bucket.arn,
          "${aws_s3_bucket.source_bucket.arn}/*",
        ]
      },
      {
        # Not needed to read the artefact. It decides which error a missing artefact produces: S3
        # answers a GetObject for an absent key with 404 to a caller that may list the bucket and
        # with 403 to one that may not, and CodePipeline passes that on as "returned a Forbidden
        # error" - which sends the reader to IAM for a problem that is an empty bucket. No
        # s3:prefix condition: GetObject carries no prefix in its request context, so a condition
        # on it never matches and the 404 never appears.
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.source_bucket.arn]
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketVersioning", "s3:GetBucketLocation"]
        Resource = [
          aws_s3_bucket.artifact_store_bucket.arn,
          "${aws_s3_bucket.artifact_store_bucket.arn}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetApplication",
          "codedeploy:GetApplicationRevision",
          "codedeploy:RegisterApplicationRevision",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentGroup",
          "codedeploy:GetDeploymentConfig",
        ]
        Resource = [
          "arn:${var.partition}:codedeploy:${var.region}:${var.account_id}:application:${aws_codedeploy_app.code_deploy_application.name}",
          # The revision calls, as the CodeDeployToECS action reference lists them. Until the seed
          # artefact existed no execution had ever reached the Deploy stage, so this half of the
          # policy had never been exercised - it follows the documented minimum rather than a
          # narrower guess.
          "arn:${var.partition}:codedeploy:${var.region}:${var.account_id}:application:${aws_codedeploy_app.code_deploy_application.name}/*",
          "arn:${var.partition}:codedeploy:${var.region}:${var.account_id}:deploymentgroup:${aws_codedeploy_app.code_deploy_application.name}/${var.code_deploy_deployment_group_name}",
          # The deployment configuration is an AWS-owned resource in this account's namespace, and
          # CodeDeployDefault.* configurations have to be named explicitly - they are not covered
          # by the application ARN.
          "arn:${var.partition}:codedeploy:${var.region}:${var.account_id}:deploymentconfig:${var.deployment_config_name}",
        ]
      },
      {
        # No resource-level permission exists for either of these: ECS evaluates
        # RegisterTaskDefinition against "*" because the task definition being created does not
        # have an ARN yet. Scoping it produces an AccessDenied that CodePipeline reports as a
        # failed Deploy action with no detail.
        Effect   = "Allow"
        Action   = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"]
        Resource = "*"
      },
      {
        # Scoped to the two roles a task definition in this project may name, and conditioned on
        # the service it may be passed to. Both halves matter: without the resource list this is
        # any role in the account, and without the condition it is these roles passed to any
        # service.
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = var.task_definition_role_arns
        # Both service principals, as the CodeDeployToECS action reference lists them. The resource
        # list is what keeps this narrow; the condition only says which service may receive them.
        Condition = {
          StringEquals = {
            "iam:PassedToService" = ["ecs-tasks.amazonaws.com", "ecs.amazonaws.com"]
          }
        }
      },
    ]
  })
}
resource "aws_codepipeline" "code_pipeline" {
  name          = var.pipeline_name
  pipeline_type = "V2"
  role_arn      = aws_iam_role.code_pipeline_iam_role.arn
  # QUEUED, as the _monolithic template had it: a second artefact uploaded while a deployment is
  # running waits rather than superseding it. SUPERSEDED would cancel the in-flight blue/green
  # switch, which is the demo.
  execution_mode = var.execution_mode
  artifact_store {
    location = aws_s3_bucket.artifact_store_bucket.id
    type     = "S3"
  }
  stage {
    name = "Source"
    action {
      name     = "SourceAction"
      category = "Source"
      owner    = "AWS"
      provider = "S3"
      version  = "1"
      configuration = {
        S3Bucket    = aws_s3_bucket.source_bucket.id
        S3ObjectKey = var.source_object_key
        # False, because the EventBridge rule below is what starts this pipeline. With it true
        # CodePipeline polls the bucket every minute instead, which also works and is the
        # deprecated path - and leaves the rule, its role and the CloudTrail data event trail in
        # the project doing nothing.
        PollForSourceChanges = "false"
      }
      output_artifacts = ["SourceOutput"]
    }
  }
  stage {
    name = "Deploy"
    action {
      name     = "DeployAction"
      category = "Deploy"
      owner    = "AWS"
      provider = "CodeDeployToECS"
      version  = "1"
      configuration = {
        ApplicationName     = aws_codedeploy_app.code_deploy_application.name
        DeploymentGroupName = aws_codedeploy_deployment_group.code_deploy_deployment_group.deployment_group_name
        # The three files the artefact has to contain. The second SSM association in the root
        # generates all three and the helper script that zips and uploads them, so the names here
        # and there have to agree - they are one variable each for that reason (rules.md B-5).
        TaskDefinitionTemplateArtifact = "SourceOutput"
        TaskDefinitionTemplatePath     = var.task_definition_template_path
        AppSpecTemplateArtifact        = "SourceOutput"
        AppSpecTemplatePath            = var.app_spec_template_path
        Image1ArtifactName             = "SourceOutput"
        # The placeholder CodePipeline substitutes in taskdef.json, taken from imageDetail.json in
        # the artefact. The container image in that file is written as <IMAGE1_NAME>, and this
        # names the variable without the angle brackets.
        Image1ContainerName = var.image_placeholder_name
      }
      input_artifacts = ["SourceOutput"]
    }
  }

  # The creation-triggered execution reads the source object within a second of CreatePipeline, so
  # the seed has to be in the bucket first. Nothing in the source action references the object -
  # the key is a variable - so without this the two are created in parallel and the pipeline wins.
  # The role policy is in the list for the same reason: role_arn orders this after the role, not
  # after the policy that lets it read the bucket (rules.md D-1).
  depends_on = [aws_s3_object.seed_artifact, aws_iam_role_policy.code_pipeline_iam_role]
}
resource "aws_iam_role" "event_rule_iam_role" {
  name_prefix = var.event_rule_role_name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["events.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
# Scoped to this stack's pipeline, where the _monolithic template had one shared role granting
# codepipeline:StartPipelineExecution on "*" (rules.md A-5). This is the narrowing the per-stack
# split buys: the resource is a single ARN because the role belongs to a single stack.
resource "aws_iam_role_policy" "event_rule_iam_role" {
  name = "StartPipelineExecutionPolicy"
  role = aws_iam_role.event_rule_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["codepipeline:StartPipelineExecution"]
      Resource = [aws_codepipeline.code_pipeline.arn]
    }]
  })
}
resource "aws_cloudwatch_event_rule" "event_rule" {
  name           = var.event_rule_name
  description    = var.event_rule_description
  event_bus_name = "default"
  state          = "ENABLED"
  # Matches a write to exactly this object in exactly this bucket. The events arrive via
  # CloudTrail - S3 does not publish data-plane events to EventBridge on its own - which is why
  # this project has a trail at all, and why that trail's data resource selector has to name the
  # same bucket and key. The trail is built in modules/cloudtrail from this module's outputs.
  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["s3.amazonaws.com"]
      eventName   = ["CopyObject", "PutObject", "CompleteMultipartUpload"]
      requestParameters = {
        bucketName = [aws_s3_bucket.source_bucket.id]
        key        = [var.source_object_key]
      }
    }
  })
}
resource "aws_cloudwatch_event_target" "event_target" {
  rule     = aws_cloudwatch_event_rule.event_rule.name
  arn      = aws_codepipeline.code_pipeline.arn
  role_arn = aws_iam_role.event_rule_iam_role.arn
  # Referencing the pipeline resource rather than assembling its ARN from the account, the region
  # and a literal name, which is what the _monolithic template did:
  #
  #   arn = "arn:aws:codepipeline:${region}:${account}:ws25-cd-green-pipeline"
  #
  # That string had no dependency on the pipeline, so EventBridge could be pointed at a pipeline
  # that did not exist yet, and renaming the pipeline left the target aimed at the old name. A
  # target pointing at nothing does not fail: the rule matches, the invocation fails, and the only
  # trace is the rule's FailedInvocations metric.
  target_id = "${var.stack_key}-codepipeline"

  depends_on = [aws_iam_role_policy.event_rule_iam_role]
}
