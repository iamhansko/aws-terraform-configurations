# One Fargate service behind its own ALB: the load balancer and its security group, a target group and an HTTP
# listener, and the service with its security group, execution role, log group and task definition. Called
# twice - the game server behind an internet-facing ALB that only CloudFront reaches, and the item image
# service behind an internal one that only the server reaches.
#
# The task role is not here: both services share one, and it is passed in (rules.md B-6).
locals {
  container_name = "main"
}
# --- Load balancer ------------------------------------------------------------------------------------------
resource "aws_security_group" "load_balancer" {
  name        = "${var.name}-alb-sg"
  description = "Security group for load balancer"
  vpc_id      = var.vpc_id
  tags = {
    Name = "${var.name}-alb-sg"
  }
}
# Standalone rules (rules.md F-2). Sources are literal CIDRs and prefix list IDs known at plan, so toset is safe
# (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "listener_from_cidr" {
  for_each          = toset(var.ingress_cidr_blocks)
  security_group_id = aws_security_group.load_balancer.id
  description       = "HTTP from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.listener_port
  to_port           = var.listener_port
  cidr_ipv4         = each.value
}
resource "aws_vpc_security_group_ingress_rule" "listener_from_prefix_list" {
  for_each          = toset(var.ingress_prefix_list_ids)
  security_group_id = aws_security_group.load_balancer.id
  description       = "HTTP from a managed prefix list"
  ip_protocol       = "tcp"
  from_port         = var.listener_port
  to_port           = var.listener_port
  prefix_list_id    = each.value
}
# To the target port inside the VPC only, where the _monolithic template allowed all outbound. An ALB never
# connects anywhere but its targets.
resource "aws_vpc_security_group_egress_rule" "load_balancer_to_targets" {
  security_group_id = aws_security_group.load_balancer.id
  description       = "Container port inside the VPC"
  ip_protocol       = "tcp"
  from_port         = var.container_port
  to_port           = var.container_port
  cidr_ipv4         = var.vpc_cidr_block
}
resource "aws_lb" "load_balancer" {
  load_balancer_type = "application"
  internal           = var.internal
  subnets            = var.load_balancer_subnet_ids
  security_groups    = [aws_security_group.load_balancer.id]
  idle_timeout       = var.idle_timeout_seconds
  # The _monolithic template's routing.http.drop_invalid_header_fields.enabled, which the conversion dropped
  # (an unmapped-property TODO): requests with malformed header names are rejected at the load balancer
  # instead of being passed to the service.
  drop_invalid_header_fields = true
}
resource "aws_lb_target_group" "service" {
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  health_check {
    path                = var.health_check_path
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
  # Also dropped by the conversion, and the one that matters: with two tasks behind the ALB, a player's
  # requests have to keep reaching the task holding their session, or the game state they see alternates
  # between two servers.
  stickiness {
    type    = "lb_cookie"
    enabled = true
  }
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = var.listener_port
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service.arn
  }
}
# --- Service ------------------------------------------------------------------------------------------------
resource "aws_security_group" "service" {
  name        = "${var.name}-ecs-service-sg"
  description = "Security group for ecs service"
  vpc_id      = var.vpc_id
  tags = {
    Name = "${var.name}-ecs-service-sg"
  }
}
resource "aws_vpc_security_group_ingress_rule" "container_from_load_balancer" {
  security_group_id            = aws_security_group.service.id
  description                  = "Allow inbound traffic from load balancer to container port"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = aws_security_group.load_balancer.id
}
resource "aws_vpc_security_group_egress_rule" "service_all_outbound" {
  security_group_id = aws_security_group.service.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_cloudwatch_log_group" "service" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_in_days
}
# Each service its own execution role, where the _monolithic template shared one: pulls from this service's
# repository and writes to this service's log group, nothing else.
resource "aws_iam_role" "execution" {
  name_prefix = "${substr(var.name, 0, 26)}-execution-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy" "execution" {
  name = "EcrAndCloudWatchPolicy"
  role = aws_iam_role.execution.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
        Resource = var.repository_arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.service.arn}:*"
      },
    ]
  })
}
resource "aws_ecs_task_definition" "service" {
  family                   = var.task_family
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = var.task_role_arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([{
    name      = local.container_name
    image     = var.image
    essential = true
    portMappings = [{
      containerPort = var.container_port
      hostPort      = var.container_port
      protocol      = "tcp"
    }]
    # Strings, every one of them. The _monolithic template put the container port into PORT as a number,
    # which ECS rejects - an environment value is a string - so the task definition never registered.
    environment = [for name in sort(keys(local.environment)) : { name = name, value = local.environment[name] }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}
locals {
  environment = merge({ PORT = tostring(var.container_port) }, var.environment)
}
resource "aws_ecs_service" "service" {
  # CloudFormation generated this name; Terraform requires one, so the caller derives it from the project
  # name as the _monolithic template did from the stack name.
  name            = "${var.name}-ecs-service"
  cluster         = var.cluster_name
  task_definition = aws_ecs_task_definition.service.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  network_configuration {
    assign_public_ip = false
    subnets          = var.task_subnet_ids
    security_groups  = concat([aws_security_group.service.id], var.extra_security_group_ids)
  }
  load_balancer {
    container_name   = local.container_name
    container_port   = var.container_port
    target_group_arn = aws_lb_target_group.service.arn
  }
  # CloudFormation waits for an AWS::ECS::Service to stabilise before it reports the resource created, which
  # is what the _monolithic stack did; Terraform does not unless asked.
  wait_for_steady_state = var.wait_for_steady_state
  # The listener attaches the target group to the load balancer, which ECS requires before it registers a
  # task; the execution role's policy and the egress rule are what the first task needs to pull and log. None
  # of them is ordered before the service by a reference (rules.md D-1).
  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy.execution,
    aws_vpc_security_group_egress_rule.service_all_outbound,
  ]
}
