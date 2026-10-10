# One ECS service, its task definition, its log group and the two roles around it.
#
# The _monolithic templates declared one task role and one execution role and pointed every task definition
# at them. Here each service owns its own pair, because the task role is defined by what that service's
# containers do with it: the ECS Exec permissions belong to the service that enables exec, and the
# permissions an application calls AWS with belong to that application (rules.md C-2).
#
# No data sources in this module. The awslogs region arrives as var.region from the root - the caller
# declares this module with depends_on, which would defer a data.aws_region read here to apply and make
# container_definitions unknown, replacing the task definition on every such apply (rules.md D-6).
resource "aws_cloudwatch_log_group" "ecs_task_log_group" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_in_days
}
locals {
  assume_ecs_tasks = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
  # IAM caps name_prefix at 38 characters and appends 26 of its own; the service name is cut to fit.
  role_name_stem = trimsuffix(substr(var.service_name, 0, 26), "-")
}
# Two roles, and the distinction between them is the one most worth getting right here.
#
# The task role is assumed by the process inside the container - and by the SSM agent that ECS Exec runs
# inside it. The execution role is assumed by the ECS agent on the task's behalf, before the container
# exists, to pull the image and open the log stream. Both are trusted by ecs-tasks.amazonaws.com, which is
# why they look identical and why swapping their policies produces a task that either cannot start or
# starts without the permissions it expected.
#
# name_prefix rather than the _monolithic template's "EcsTaskIamRole-<uuid slice>", which got uniqueness
# from the random_uuid standing in for AWS::StackId. IAM role names are account-wide, so uniqueness is
# needed; the provider's prefix gives it without a random provider.
resource "aws_iam_role" "ecs_task_role" {
  name_prefix        = "${local.role_name_stem}-task-"
  assume_role_policy = local.assume_ecs_tasks
}
# What ECS Exec needs from the task role, and only when the service enables it.
#
# The ssmmessages statement is the _monolithic template's EcsExecPolicy, unchanged: an exec session is a
# pair of websocket channels the SSM agent inside the task opens to ssmmessages, as the task role. Without
# it the task starts normally, its ExecuteCommandAgent reports RUNNING, and every execute-command fails
# with TargetNotConnectedException.
#
# The log statements are an addition. The cluster declares no execute_command_configuration, so session
# logging is DEFAULT, under which ECS sends each session's commands and output to the awslogs group in the
# task definition - written with this role, not the execution role, and only when the image has the script
# and cat utilities the upload runs. The template granted nothing for it, so its sessions worked and their
# logging could not. They are scoped to this service's own log group.
resource "aws_iam_role_policy" "ecs_task_role_execute_command" {
  count = var.enable_execute_command ? 1 : 0

  name = "EcsExecPolicy"
  role = aws_iam_role.ecs_task_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.ecs_task_log_group.arn}:*"
      },
    ]
  })
}
# for_each over the list rather than one attachment per policy (rules.md B-7). toset is safe because
# these are literal strings in configuration and known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "ecs_task_role" {
  for_each   = toset(var.task_role_policy_arns)
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = each.value
}
resource "aws_iam_role" "ecs_task_execution_role" {
  name_prefix        = "${local.role_name_stem}-exec-"
  assume_role_policy = local.assume_ecs_tasks
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  for_each   = toset(var.task_execution_role_policy_arns)
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = each.value
}
locals {
  # The container definition in the API's own camelCase. The _monolithic template wrote PascalCase keys
  # (Name, Image, LogConfiguration), which RegisterTaskDefinition accepts, but which is not what
  # DescribeTaskDefinition returns - writing what comes back leaves the comparison nothing to normalise.
  #
  # Optional keys are left out rather than set to null, because a null written into the JSON is a value
  # the API never returns.
  container_definition = merge(
    {
      name      = var.container_name
      image     = var.image
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_task_log_group.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = var.log_stream_prefix
        }
      }
    },
    var.entry_point == null ? {} : { entryPoint = var.entry_point },
    # A named port mapping, which is what Service Connect discovers by: the service's port_name below is
    # this same name, taken from the same variable, so the two cannot disagree.
    var.container_port == null ? {} : {
      portMappings = [{
        name          = var.port_mapping_name
        containerPort = var.container_port
        protocol      = "tcp"
      }]
    },
    # An init process as PID 1, which the ECS Exec documentation recommends and the _monolithic template
    # did not set. Each exec session starts the SSM agent's child processes inside the container; with the
    # container's own command as PID 1 nothing reaps them when a session ends, and they accumulate for the
    # life of the task.
    var.enable_execute_command ? { linuxParameters = { initProcessEnabled = true } } : {},
  )
}
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family = var.task_family
  # The ARNs. The _monolithic template passed aws_iam_role.<role>.name into both of these. ECS accepts a
  # bare role name in RegisterTaskDefinition and resolves it, but DescribeTaskDefinition returns the full
  # ARN, so the value in state never matches the configuration - and both attributes force replacement,
  # so every plan after the first proposes registering a new revision and rolling the service onto it.
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  # A genuine JSON array - container_definitions takes a list of container objects - rather than the
  # CloudFormation list squeezed into a scalar attribute that rules.md A-3 warns about.
  container_definitions = jsonencode([local.container_definition])

  # The log group is named as a string inside container_definitions, so the reference above does order
  # this after it - but only because the name is read from the resource rather than from the variable
  # (rules.md D-1). The role policies are not implied by the ARNs at all: a task started before them would
  # run without ECS Exec permissions or without its application policy, and an exec session against it
  # would fail until the next deployment.
  depends_on = [
    aws_cloudwatch_log_group.ecs_task_log_group,
    aws_iam_role_policy.ecs_task_role_execute_command,
    aws_iam_role_policy_attachment.ecs_task_role,
    aws_iam_role_policy_attachment.ecs_task_execution_role,
  ]
}
resource "aws_ecs_service" "ecs_service" {
  name            = var.service_name
  cluster         = var.cluster_name
  task_definition = aws_ecs_task_definition.ecs_task_definition.arn
  desired_count   = var.desired_count
  # awsvpc on the EC2 launch type: each task gets its own ENI in the task security group, in the private
  # subnets, with no public address - EC2 awsvpc tasks cannot take one, so assign_public_ip stays false and
  # their outbound goes through the NAT gateways like the instances' does.
  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }
  # No launch_type: launch_type and capacity_provider_strategy are mutually exclusive.
  capacity_provider_strategy {
    # The name, not the ARN. The _monolithic template wrote aws_ecs_capacity_provider.x.id here, and that
    # resource's id is its ARN - ECS documents this field as the provider's short name and returns the
    # name, so an ARN leaves a difference between configuration and state that never settles.
    capacity_provider = var.capacity_provider_name
    base              = var.capacity_provider_base
    weight            = var.capacity_provider_weight
  }
  enable_execute_command  = var.enable_execute_command
  enable_ecs_managed_tags = var.enable_ecs_managed_tags
  # Written out even when disabled: turning Service Connect off on a service that had it on requires an
  # explicitly disabled block, because an absent block leaves the existing configuration untouched.
  service_connect_configuration {
    enabled   = var.service_connect != null
    namespace = try(var.service_connect.namespace, null)
    # The server half - an endpoint other services reach this one by. Absent for a client-only service,
    # which joins the namespace only to get the proxy that resolves the other services' aliases.
    dynamic "service" {
      for_each = try(var.service_connect.server, null) == null ? [] : [var.service_connect.server]
      content {
        # The port mapping's name, from the same variable the task definition's portMappings uses. A
        # port_name that names no mapping is rejected by CreateService at apply, not by plan.
        port_name      = var.port_mapping_name
        discovery_name = service.value.discovery_name
        client_alias {
          port     = service.value.client_alias_port
          dns_name = service.value.client_alias_dns_name
        }
      }
    }
  }
  # Cloud Map registration, for a service discovered by DNS rather than through Service Connect. An object
  # rather than a bare ARN so that whether the block exists is known at plan while the ARN is not.
  dynamic "service_registries" {
    for_each = var.service_registry == null ? [] : [var.service_registry]
    content {
      registry_arn = service_registries.value.registry_arn
    }
  }
  dynamic "ordered_placement_strategy" {
    for_each = var.placement_strategies
    content {
      type  = ordered_placement_strategy.value.type
      field = ordered_placement_strategy.value.field
    }
  }
  wait_for_steady_state = var.wait_for_steady_state
}
