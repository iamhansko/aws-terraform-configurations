# One ECS service on the managed instances capacity provider, with its task definition, log group, roles and
# security group. Called twice: once for Shlink and once for the web client.
#
# Each call gets its own execution role. The _monolithic template shared one between both services, which
# meant either service's agent could read anything the other needed; here each role is granted the one
# secret its task definition names, and only the service that mounts EFS has a task role at all.
locals {
  assume_ecs_tasks = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  mounts_efs = var.efs_volume != null
}
resource "aws_cloudwatch_log_group" "service" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_in_days
}
# --- Execution role: the agent's identity for pulling, logging and resolving secrets ----------------------
resource "aws_iam_role" "task_execution" {
  name_prefix        = "${trimsuffix(substr(var.name, 0, 22), "-")}-execution-"
  assume_role_policy = local.assume_ecs_tasks
}
resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
# The secrets entries in the container definition are resolved by the agent with this role, before the
# container starts. Without it the task stops with ResourceInitializationError naming the secret.
resource "aws_iam_role_policy" "task_execution_secret" {
  count = length(var.secrets) > 0 ? 1 : 0
  name  = "AllowSecretManagerGetSecretValue"
  role  = aws_iam_role.task_execution.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = var.secret_arn
    }]
  })
}
# --- Task role: only for a service that mounts EFS with IAM authorization ---------------------------------
resource "aws_iam_role" "task" {
  count              = local.mounts_efs ? 1 : 0
  name_prefix        = "${trimsuffix(substr(var.name, 0, 27), "-")}-task-"
  assume_role_policy = local.assume_ecs_tasks
}
# What iam = "ENABLED" on the volume checks: mount and write, and only through this access point.
resource "aws_iam_role_policy" "task_efs" {
  count = local.mounts_efs ? 1 : 0
  name  = "AllowEfsClient"
  role  = aws_iam_role.task[0].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
      Resource = var.efs_volume.file_system_arn
      Condition = {
        StringEquals = { "elasticfilesystem:AccessPointArn" = var.efs_volume.access_point_arn }
      }
    }]
  })
}
# --- Security group for the tasks -------------------------------------------------------------------------
resource "aws_security_group" "service" {
  name        = var.security_group_name
  description = "Security Group for the ${var.name} tasks"
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# A map keyed by a caller-chosen label, because the sources are other modules' security groups and their IDs
# are unknown until apply (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "container_port_from_source" {
  for_each                     = var.ingress_source_security_groups
  security_group_id            = aws_security_group.service.id
  description                  = "Container port from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = each.value
}
# The rule the _monolithic template's task groups did not have. Terraform removes the allow-all egress AWS
# puts on a new group, so the tasks could not pull from Docker Hub, reach Secrets Manager or open NFS to the
# mount targets - each task stopped before its container started.
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.service.id
  description       = "Image pulls, Secrets Manager, CloudWatch Logs and NFS"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# --- Task definition and service --------------------------------------------------------------------------
resource "aws_ecs_task_definition" "task_definition" {
  family                   = var.task_family
  requires_compatibilities = ["MANAGED_INSTANCES"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = one(aws_iam_role.task[*].arn)
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
  # camelCase keys, as the ECS API documents them. Optional parts are merged in only when set, so a service
  # without a health check or a volume does not carry empty keys that read back as a diff.
  container_definitions = jsonencode([merge(
    {
      name      = var.container_name
      image     = var.container_image
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.service.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
          mode                    = "non-blocking"
          "max-buffer-size"       = "25m"
        }
      }
      portMappings = [{
        containerPort = var.container_port
        protocol      = "tcp"
      }]
    },
    length(var.secrets) == 0 ? {} : {
      secrets = [for name in sort(keys(var.secrets)) : {
        name      = name
        valueFrom = "${var.secret_arn}:${var.secrets[name]}::"
      }]
    },
    var.container_health_check == null ? {} : {
      healthCheck = {
        command     = var.container_health_check.command
        interval    = var.container_health_check.interval
        timeout     = var.container_health_check.timeout
        retries     = var.container_health_check.retries
        startPeriod = var.container_health_check.start_period
      }
    },
    local.mounts_efs ? {
      mountPoints = [{
        sourceVolume  = var.efs_volume.name
        containerPath = var.efs_volume.container_path
        readOnly      = false
      }]
    } : {},
  )])
  dynamic "volume" {
    for_each = local.mounts_efs ? [var.efs_volume] : []
    content {
      name = volume.value.name
      efs_volume_configuration {
        file_system_id     = volume.value.file_system_id
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = volume.value.access_point_id
          iam             = "ENABLED"
        }
      }
    }
  }
}
resource "aws_ecs_service" "service" {
  # CloudFormation generated this name; Terraform requires one, so the caller derives it from the project
  # name as the _monolithic template did from the stack name.
  name            = var.name
  cluster         = var.cluster_name
  task_definition = aws_ecs_task_definition.task_definition.arn
  desired_count   = var.desired_count
  capacity_provider_strategy {
    capacity_provider = var.capacity_provider_name
    weight            = 100
  }
  network_configuration {
    subnets         = var.subnet_ids
    security_groups = concat([aws_security_group.service.id], var.extra_security_group_ids)
  }
  load_balancer {
    container_name   = var.container_name
    container_port   = var.container_port
    target_group_arn = var.target_group_arn
  }
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  # CloudFormation waits for an AWS::ECS::Service to stabilise before it reports the resource created, which
  # is what the _monolithic stack did; Terraform does not unless asked.
  wait_for_steady_state = var.wait_for_steady_state
  # The policies and the egress rule the first task needs, none of which the references above order this
  # after (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.task_execution,
    aws_iam_role_policy.task_execution_secret,
    aws_iam_role_policy.task_efs,
    aws_vpc_security_group_egress_rule.all_outbound,
  ]
}
