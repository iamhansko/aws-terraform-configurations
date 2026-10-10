locals {
  # Every port this group admits: the container port, plus whatever else the caller asks for. One value
  # for the container port rather than two, so the port the task listens on, the port the task
  # definition publishes and the port the rule opens cannot diverge (rules.md B-5).
  ingress_ports = merge({ http = var.container_port }, var.additional_ingress_ports)

  # One rule per source group and port pair. Both maps are keyed by labels that are literals in
  # configuration, so the composed key is known at plan time even though the group IDs behind the
  # values are not - which is the shape rules.md B-8 requires.
  source_group_ingress_rules = {
    for pair in setproduct(keys(var.ingress_source_security_groups), keys(local.ingress_ports)) :
    "${pair[0]}-${pair[1]}" => {
      source_label      = pair[0]
      security_group_id = var.ingress_source_security_groups[pair[0]]
      port_label        = pair[1]
      port              = local.ingress_ports[pair[1]]
    }
  }
}
# The security group every task's elastic network interface gets.
#
# With awsvpc networking this is the group that matters, and it is easy to reach for the container
# instance group instead: a task gets its own interface in a private subnet, and this group - not the
# instance's - is what the load balancer has to get past to reach the container port, and what the
# task's own outbound calls leave through.
resource "aws_security_group" "ecs_service_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress blocks (rules.md F-2).
#
# The _monolithic template gave this group two inline ingress blocks and no egress block. CloudFormation
# leaves EC2's allow-all outbound rule in place when a template names only SecurityGroupIngress;
# Terraform's inline blocks are authoritative over the whole group and revoke it instead.
#
# With awsvpc that is the single most damaging instance of the bug in this project, because every task
# has its own interface and loses outbound individually. The execution role's ECR pull cannot leave, so
# the task stops with CannotPullContainerError against an image that is present and a role that is
# correct. The awslogs driver's call to CloudWatch Logs fails the same way, which means the log stream
# that would have explained it does not exist either. The service then replaces the task and does it
# again, indefinitely, and apply reported success several minutes earlier.
resource "aws_vpc_security_group_egress_rule" "ecs_service_egress" {
  security_group_id = aws_security_group.ecs_service_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_ingress_rule" "ecs_service_source_group_ingress" {
  for_each = local.source_group_ingress_rules

  security_group_id            = aws_security_group.ecs_service_security_group.id
  description                  = "${each.value.port_label} port from the ${each.value.source_label} security group"
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = each.value.security_group_id
}
# The execution role, assumed by the ECS agent on the task's behalf before the container exists, to
# pull the image and open the log stream. There is no task role here and that is accurate: the Go
# application makes no AWS API call at all, so a task role would be an empty role.
resource "aws_iam_role" "ecs_task_execution_role" {
  # A generated name. The _monolithic template left this role unnamed, which the provider handles by
  # generating one anyway - a prefix at least says what it is in an IAM listing.
  name_prefix = var.execution_role_name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
# for_each over the list rather than one attachment per policy (rules.md B-7). toset is safe because
# these are literal strings in configuration and known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  for_each   = toset(var.execution_role_policy_arns)
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = each.value
}
resource "aws_cloudwatch_log_group" "ecs_task_log_group" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_in_days
  tags = {
    Name = var.log_group_name
  }
}
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family             = var.task_family
  cpu                = tostring(var.task_cpu)
  memory             = tostring(var.task_memory)
  network_mode       = "awsvpc"
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  # No requires_compatibilities, which is deliberate rather than inherited. Omitted, ECS infers EC2,
  # and that matches the task definition the CodeBuild buildspec registers on every pipeline run -
  # which also omits it. Setting EC2 here and leaving the buildspec alone would make the revision this
  # apply registers differ from every revision after it in a field nothing would explain.
  #
  # camelCase keys, where the _monolithic template carried CloudFormation's PascalCase - Name, Image,
  # PortMappings, HealthCheck. The ECS API tolerates both, because the SDK unmarshals this JSON
  # case-insensitively, so the template worked; camelCase is what RegisterTaskDefinition documents and
  # what the API returns, which is also what the provider compares against when it decides whether this
  # attribute has changed.
  container_definitions = jsonencode([{
    name      = var.container_name
    image     = var.image_uri
    essential = true
    healthCheck = {
      # Runs inside the container, so curl has to be present in the image - the golang base image the
      # build uses has it. A container whose health check command is missing reports unhealthy forever
      # and ECS replaces it in a loop.
      command = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
      # The _monolithic template gave this block a command and nothing else, taking the ECS defaults,
      # while the task definition its buildspec registers sets all four. These are the buildspec's
      # values, so that the revision this apply registers behaves the same as every revision the
      # pipeline registers after it.
      interval    = var.container_health_check_interval
      timeout     = var.container_health_check_timeout
      retries     = var.container_health_check_retries
      startPeriod = var.container_health_check_start_period
    }
    portMappings = [{
      containerPort = var.container_port
      # Equal to containerPort because the network mode is awsvpc, where the task has its own interface
      # and there is no port translation. A different value is rejected at RegisterTaskDefinition.
      hostPort = var.container_port
      protocol = "tcp"
    }]
    # Added. The _monolithic template created this log group, had the service depend on it, and then
    # registered a task definition with no logConfiguration at all - while the task definition its
    # buildspec registers writes to exactly this group. So the group existed and only the revisions the
    # pipeline produced ever wrote to it, which means the tasks running immediately after the first
    # apply - the ones most likely to be failing - were the only ones with no logs.
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs_task_log_group.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = var.log_stream_prefix
      }
    }
  }])

  # The log group name is read from the resource above, so the interpolation already orders this after
  # it. The explicit edge keeps that true if the interpolation is ever changed to the variable, which
  # would be a literal with no edge at all - and the awslogs driver's response to a group that does not
  # exist yet is to fail the container start with a ResourceNotFoundException (rules.md D-1).
  depends_on = [aws_cloudwatch_log_group.ecs_task_log_group]
}
# The service, and the resource where CodeDeploy and Terraform share ownership.
resource "aws_ecs_service" "ecs_service" {
  name = var.service_name
  # The cluster name arrives as a variable the caller takes from the cluster module's output. The
  # _monolithic template wrote the literal "stem-cluster" here, which is accepted and creates no edge at
  # all - so the service could be created before the cluster, and on destroy could outlive it.
  cluster             = var.cluster_name
  task_definition     = aws_ecs_task_definition.ecs_task_definition.arn
  desired_count       = var.desired_count
  scheduling_strategy = var.scheduling_strategy
  # CODE_DEPLOY, which is what makes everything else in this project necessary: with the default ECS
  # controller there would be one target group and no CodeDeploy application at all. ECS validates the
  # shape at CreateService and requires exactly one load_balancer block, naming the currently live
  # target group.
  deployment_controller {
    type = "CODE_DEPLOY"
  }
  # No launch_type, which is not an omission: launch_type and capacity_provider_strategy are mutually
  # exclusive and setting both fails at apply.
  capacity_provider_strategy {
    # The name, not the ARN. The _monolithic template wrote the capacity provider resource's id here,
    # and that id is its ARN - ECS documents this field as the provider's short name and returns the
    # name, so an ARN leaves a difference between configuration and state that never settles. The
    # ecs_asg_capacity_provider module makes the same correction in the cluster association.
    capacity_provider = var.capacity_provider_name
    base              = var.capacity_provider_base
    weight            = var.capacity_provider_weight
  }
  network_configuration {
    assign_public_ip = false
    security_groups  = [aws_security_group.ecs_service_security_group.id]
    subnets          = var.subnet_ids
  }
  load_balancer {
    container_name   = var.container_name
    container_port   = var.container_port
    target_group_arn = var.blue_target_group_arn
  }
  enable_ecs_managed_tags = var.enable_ecs_managed_tags
  # Written out even when disabled: turning Service Connect off on a service that had it on requires an
  # explicitly disabled block, because an absent block leaves the existing configuration untouched.
  service_connect_configuration {
    enabled = var.enable_service_connect
  }
  # Ordered, and the order is the meaning: ECS applies these in sequence, so zones are balanced first
  # and only then instances within a zone. Reversing them would fill one zone's instances before using
  # the other zone at all, which during a blue/green deployment would put the replacement task set in
  # whichever zone had room rather than spread across both.
  ordered_placement_strategy {
    field = "attribute:ecs.availability-zone"
    type  = "spread"
  }
  ordered_placement_strategy {
    field = "instanceId"
    type  = "spread"
  }

  lifecycle {
    # The two fields CodeDeploy owns once the first deployment has run.
    #
    # A deployment registers a new task definition revision - the buildspec's post_build does that
    # explicitly - and moves the service to it, and it swaps the target group in the service's load
    # balancer configuration as it shifts traffic. Terraform recorded the revision it created and the
    # blue target group, so without this every plan after a deployment proposes rolling the service
    # back to both of them. Applying that plan undoes the deployment while CodeDeploy still believes it
    # succeeded, and because the deployment group terminates the blue task set immediately
    # (termination_wait_time_in_minutes is zero) there is nothing to roll back to.
    #
    # This is the same argument rules.md E-8 makes for a controller-owned field, with one difference
    # that matters: there the advice is to exclude the single path rather than the whole object, and
    # here task_definition and load_balancer already are single attributes, so naming them is as narrow
    # as it gets. Everything else stays tracked - desired_count, the subnets, the security group, the
    # capacity provider strategy - so a change to any of those is still a plan.
    #
    # Note which resource is not in this list: the task definition above. Terraform keeps owning the
    # revision it registers, which is what the first deployment starts from; the revisions CodeDeploy
    # deploys are registered by CodeBuild and are not Terraform resources at all.
    ignore_changes = [task_definition, load_balancer]
  }

  # Three things that no reference in this resource implies.
  #
  #   - the execution role's policy. The task definition records the role ARN and ECS accepts a role
  #     with no policy; the failure arrives later as a task that stops with CannotPullContainerError
  #     (rules.md D-1)
  #   - the group's own egress rule, for the reason the rule describes. A service created while the
  #     group has no outbound starts replacing tasks immediately
  #   - the log group, which the awslogs driver needs before the first container starts
  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_role,
    aws_vpc_security_group_egress_rule.ecs_service_egress,
    aws_cloudwatch_log_group.ecs_task_log_group,
  ]
}
