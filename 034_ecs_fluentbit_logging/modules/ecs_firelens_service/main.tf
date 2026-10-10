# Two roles, and the distinction between them is the single thing most worth getting right in this
# module. They look identical - both are trusted by ecs-tasks.amazonaws.com - and they are used by
# different principals at different times.
#
#   The task role is assumed by the processes inside the containers. Here that means Fluent Bit: the
#   cloudwatch_logs output plugin signs its PutLogEvents calls with these credentials. Every permission
#   this project needs for its actual log delivery belongs on this role.
#
#   The task execution role is assumed by the ECS agent on the task's behalf, before any container
#   exists, to pull the images and to open the log stream for any container using the awslogs driver.
#   Here that is the log router's own stdout going to its own group.
#
# The _monolithic template attached CloudWatchFullAccessV2 to both, which is why swapping them would have
# made no difference there - and is also why neither attachment said anything about what either role
# needs. Narrowing them (rules.md A-5) is what makes the split legible: the task role carries one policy
# scoped to one log group, and the execution role carries the standard managed policy and nothing else.
resource "aws_iam_role" "ecs_task_role" {
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
# A map keyed by a caller-chosen label rather than a list, and the reason is the source of the values
# rather than a preference. The policy this role needs is created by the log destination module, so its
# ARN is another module's output and is unknown at plan time - toset() over it would make the value its
# own for_each key and the plan would fail (rules.md B-8). The execution role below takes a list, because
# its policies are literal ARNs in configuration (rules.md B-7). The two rules split on where the value
# comes from, not on which role it is for.
resource "aws_iam_role_policy_attachment" "ecs_task_role" {
  for_each   = var.task_role_policy_arns
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = each.value
}
resource "aws_iam_role" "ecs_task_execution_role" {
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
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  for_each   = toset(var.task_execution_role_policy_arns)
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = each.value
}
locals {
  # The application container. Its stdout is the subject of the whole project.
  #
  # awsfirelens is not a Docker log driver - it is a task definition shorthand. The ECS agent reads these
  # options, generates a Fluent Bit configuration file with a matching [OUTPUT] section, mounts it into
  # the log router at /fluent-bit/etc/fluent-bit.conf, and rewrites this container's actual log driver to
  # fluentd pointed at a Unix socket the router listens on. That generated file ends up on the container
  # instance under /var/lib/ecs/data/firelens/<task-id>/config, which is worth knowing because it is the
  # only place to see what these options actually became.
  application_container = {
    Name      = var.application_container_name
    Image     = var.application_image_uri
    Essential = true
    LogConfiguration = {
      LogDriver = "awsfirelens"
      Options   = var.application_firelens_options
    }
    # A container dependency, which the _monolithic template did not have, and in bridge network mode it
    # is needed rather than tidy.
    #
    # Nothing otherwise orders these two containers. If this one starts first, the fluentd driver has no
    # socket to connect to yet. The agent's default ECS_ENABLE_FIRELENS_ASYNC is true, so that does not
    # fail the container - the driver connects in the background and the lines written in the meantime
    # are dropped. This application prints its first line immediately, so without this dependency the
    # beginning of the stream is quietly missing on every task start, and nothing anywhere reports it.
    #
    # START rather than HEALTHY: the AWS for Fluent Bit image declares no health check, so a HEALTHY
    # condition would never be satisfied and the task would sit until the agent gave up on it.
    DependsOn = [{
      ContainerName = var.log_router_container_name
      Condition     = "START"
    }]
  }
  # The log router. Its own stdout goes to CloudWatch by the ordinary awslogs driver, because it cannot
  # route its own startup failures through itself.
  log_router_container = {
    Name      = var.log_router_container_name
    Image     = var.log_router_image_uri
    Essential = true
    FirelensConfiguration = {
      Type = var.firelens_type
    }
    LogConfiguration = {
      LogDriver = "awslogs"
      Options   = var.log_router_awslogs_options
    }
    # sort(keys(...)) so the rendered JSON does not reorder between plans on a map whose iteration order
    # Terraform does not promise, which would show up as a task definition revision with no change in it.
    Environment = [for name in sort(keys(var.log_router_environment)) : {
      Name  = name
      Value = var.log_router_environment[name]
    }]
    # A soft limit, which the _monolithic template did not set. Both containers shared the task's 1024
    # MiB with no reservation of their own, so ECS had nothing to place against per container. 50 MiB is
    # the figure AWS's own FireLens guidance uses for a sidecar at this throughput.
    MemoryReservation = var.log_router_memory_reservation
  }
}
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family                   = var.task_family
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  network_mode             = var.network_mode
  requires_compatibilities = ["EC2"]
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  runtime_platform {
    cpu_architecture        = var.cpu_architecture
    operating_system_family = "LINUX"
  }
  # No portMappings on either container, which is correct and is also a FireLens requirement rather than
  # only a consequence of the application having no listener. The log router listens on 24224 for the
  # forward protocol, and AWS's guidance for bridge mode is not to map that port - publishing it would
  # make one task's log router reachable from outside the task (rules.md F-2 is about the same class of
  # mistake on the security group side).
  container_definitions = jsonencode([
    local.application_container,
    local.log_router_container,
  ])
  # The two image references are strings inside container_definitions, so the references above order this
  # after nothing in particular - the images are built by an SSM association in the root, and the caller
  # is what orders this module after it (rules.md D-2). The policy attachments are a different matter:
  # ECS validates the roles when the task definition is registered, and an execution role without its
  # policy is accepted here and then fails at the first pull (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_role,
    aws_iam_role_policy_attachment.ecs_task_execution_role,
  ]
}
# The service, which keeps desired_count copies of the task running.
#
# No load balancer, no target group and no port, and that is right for this project rather than something
# missing. The application is a loop that prints a JSON line to stdout and sleeps; it has no listener, so
# there is nothing an ALB could health-check and nothing a client could call. The result the project
# produces is read out of CloudWatch Logs, which is where the root's outputs point.
#
# The _monolithic template also declared an aws_security_group named ecs_service_security_group and then
# referenced it from nothing. It could not have been used: a security group reaches a task only through a
# network_configuration block, which exists only for awsvpc network mode, and this task definition uses
# bridge. In bridge mode the tasks share the container instance's network namespace, so the container
# instance's group in the ecs_asg_capacity_provider module is the tasks' group. That group is reproduced;
# the unattachable one is not, because a group that nothing can be attached to is a thing the next reader
# has to work out rather than read.
resource "aws_ecs_service" "ecs_service" {
  name            = var.service_name
  cluster         = var.cluster_name
  task_definition = aws_ecs_task_definition.ecs_task_definition.arn
  desired_count   = var.desired_count
  # No launch_type, which is a change from the _monolithic template's launch_type = "EC2" rather than an
  # omission - the two arguments are mutually exclusive and setting both fails at apply.
  #
  # That template declared a capacity provider, made it the cluster's default strategy, and then set
  # launch_type on the service, which bypasses the default strategy entirely. The capacity provider was
  # therefore inert: ECS never saw this service's task demand, so managed scaling had nothing to act on.
  # Naming the provider here is what connects the two halves that template built.
  capacity_provider_strategy {
    # The name, not the ARN. The _monolithic template wrote the capacity provider resource's .id into
    # both this field and the cluster association, and that resource's id is its ARN - see the comment on
    # aws_ecs_cluster_capacity_providers in the ecs_asg_capacity_provider module for what that costs.
    capacity_provider = var.capacity_provider_name
    base              = var.capacity_provider_base
    weight            = var.capacity_provider_weight
  }
  wait_for_steady_state = var.wait_for_steady_state
}
