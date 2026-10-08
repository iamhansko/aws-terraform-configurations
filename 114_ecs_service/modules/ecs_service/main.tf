# The Fargate service, its task definition, the three roles around them and the tasks' security group.
#
# The roles are here rather than in a module of their own because each one is defined by what this service
# does with it: the execution role pulls and logs for this task definition, the task role is what ECS Exec
# runs as inside these containers, and the infrastructure role exists only for this service's
# advanced_configuration. None of them is shared with anything else (rules.md C-2).
locals {
  assume_ecs_tasks = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
# --- Execution role: what the ECS agent uses to pull the image and ship the logs ---------------------------
resource "aws_iam_role" "task_execution" {
  name_prefix        = "${trimsuffix(substr(var.name, 0, 20), "-")}-execution-"
  assume_role_policy = local.assume_ecs_tasks
}
resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
# --- Task role: what the containers - and an ECS Exec session inside them - run as -----------------------
resource "aws_iam_role" "task" {
  name_prefix        = "${trimsuffix(substr(var.name, 0, 25), "-")}-task-"
  assume_role_policy = local.assume_ecs_tasks
}
# What enable_execute_command needs, which the _monolithic template never granted.
#
# It attached AmazonECSInfrastructureRolePolicyForVolumes to this role instead. That policy is written for the
# ECS infrastructure role - its statements are EBS volume management for ecs.amazonaws.com to perform - and on
# a task role trusted by ecs-tasks.amazonaws.com it grants the containers the ability to create and attach EBS
# volumes while granting nothing ECS Exec uses. So the service had exec enabled and every execute-command
# failed with TargetNotConnectedException: the SSM agent inside the task could not open its channels.
#
# The log statements are for execute_command_logging = DEFAULT, under which the session output goes to the
# task's own awslogs group, written with this role rather than the execution role.
resource "aws_iam_role_policy" "task_execute_command" {
  name = "EcsExec"
  role = aws_iam_role.task.name
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
        Resource = "${var.log_group_arn}:*"
      },
    ]
  })
}
# --- Infrastructure role: what ECS uses to manage the listener rule and the alternate target group -------
resource "aws_iam_role" "load_balancer_infrastructure" {
  name_prefix = "${trimsuffix(substr(var.name, 0, 24), "-")}-lb-infra-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "load_balancer_infrastructure" {
  role       = aws_iam_role.load_balancer_infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"
}
# --- Security group for the tasks -------------------------------------------------------------------------
resource "aws_security_group" "service" {
  name        = var.security_group_name
  description = "Security Group for the ECS service tasks"
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# A map keyed by a caller-chosen label rather than a list, because the source is another module's security
# group and its ID is unknown until apply (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "container_port_from_source" {
  for_each                     = var.ingress_source_security_groups
  security_group_id            = aws_security_group.service.id
  description                  = "Container port from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = each.value
}
# The rule the _monolithic template's group did not have. Terraform removes the allow-all egress AWS puts on a
# new group, so its tasks could not reach Docker Hub, and every one of them stopped with
# CannotPullContainerError before nginx started.
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.service.id
  description       = "Image pulls, CloudWatch Logs and ECS Exec through the NAT gateway"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# --- Task definition and service --------------------------------------------------------------------------
resource "aws_ecs_task_definition" "task_definition" {
  family                   = var.task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  task_role_arn            = aws_iam_role.task.arn
  execution_role_arn       = aws_iam_role.task_execution.arn
  # camelCase keys, which is what the ECS API documents. The _monolithic template's PascalCase keys were
  # accepted only because the provider's JSON decoding is case-insensitive.
  container_definitions = jsonencode([{
    name      = var.container_name
    image     = var.container_image
    essential = true
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = var.log_group_name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = var.log_stream_prefix
      }
    }
    portMappings = [{
      name          = "http"
      protocol      = "tcp"
      containerPort = var.container_port
    }]
  }])
  # The _monolithic template carried depends_on = [aws_instance.vs_code_ec2] here, a CloudFormation DependsOn
  # with nothing behind it - the task definition uses nothing from the instance. It is not reproduced.
}
resource "aws_ecs_service" "service" {
  # CloudFormation generated this name; Terraform requires one, so the caller derives it from the project
  # name as the _monolithic template did from the stack name.
  name                              = var.name
  cluster                           = var.cluster_name
  task_definition                   = aws_ecs_task_definition.task_definition.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  platform_version                  = "LATEST"
  scheduling_strategy               = "REPLICA"
  enable_execute_command            = true
  availability_zone_rebalancing     = var.availability_zone_rebalancing
  health_check_grace_period_seconds = var.health_check_grace_period_seconds
  deployment_controller {
    type = "ECS"
  }
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = false
  }
  load_balancer {
    container_name   = var.container_name
    container_port   = var.container_port
    target_group_arn = var.target_group_arn
    advanced_configuration {
      role_arn                   = aws_iam_role.load_balancer_infrastructure.arn
      alternate_target_group_arn = var.alternate_target_group_arn
      production_listener_rule   = var.production_listener_rule_arn
    }
  }
  # CloudFormation waits for an AWS::ECS::Service to reach a steady state before it calls the resource
  # created; Terraform does not unless told to. True reproduces what the original stack did.
  wait_for_steady_state = var.wait_for_steady_state
  # Three things the references above do not order this after (rules.md D-1):
  #   - the infrastructure role's policy, which ECS checks when the service is created
  #   - the task role's policy, without which the first tasks start with exec channels that cannot open
  #   - the egress rule, without which the first tasks fail to pull and the circuit breaker counts them
  depends_on = [
    aws_iam_role_policy_attachment.load_balancer_infrastructure,
    aws_iam_role_policy_attachment.task_execution,
    aws_iam_role_policy.task_execute_command,
    aws_vpc_security_group_egress_rule.all_outbound,
  ]
}
