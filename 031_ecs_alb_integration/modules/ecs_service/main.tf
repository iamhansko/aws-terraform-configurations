# The Fargate service, its task definition, the execution role the ECS agent uses on its behalf, and the
# security group its network interfaces get.
#
# The role is here rather than in a module of its own because it is defined by what this task definition
# does with it - pulling this image and opening this log stream - and is shared with nothing else
# (rules.md C-2).
#
# The region the awslogs driver is told to write to, and the one data source this module has.
#
# The caller declares this module with depends_on, which defers every data source in it to apply
# (rules.md D-6). That is harmless for this one: the value ends up as a string inside a container
# definition, not as a resource address and not as a for_each or count key, so nothing needs it at plan
# time. A data source whose result shaped a resource address would have to be lifted into the root instead.
data "aws_region" "current" {}
# The log group, which is an addition to the _monolithic template rather than a transcription of it.
#
# That container definition had no logConfiguration at all. On Fargate there is no instance to run
# "docker logs" on, so a container's stdout with no log driver configured goes nowhere: a task whose Flask
# process exits immediately shows up as a stopped task with "Essential container in task exited" and no
# further detail anywhere in the console, the CLI or Terraform. This project's whole point is watching the
# service through CloudWatch, and the one thing it could not see was the container itself.
resource "aws_cloudwatch_log_group" "task" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_in_days
}
resource "aws_iam_role" "task_execution" {
  name_prefix = var.iam_role_name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ecs-tasks.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
# for_each over the policy list rather than one attachment resource per policy, so a caller can add or
# remove a policy without this module changing (rules.md B-7). toset is safe because these ARNs are literal
# strings in configuration and so are known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "task_execution" {
  for_each   = toset(var.task_execution_role_policy_arns)
  role       = aws_iam_role.task_execution.name
  policy_arn = each.value
}
resource "aws_security_group" "service" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# A map keyed by a caller-chosen label rather than a list, because the source is another module's security
# group and its ID is unknown until apply - which cannot be a for_each key (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "container_port_from_source" {
  for_each                     = var.ingress_source_security_groups
  security_group_id            = aws_security_group.service.id
  description                  = "Container port from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = each.value
}
# The rule the _monolithic template's group did not have. It declared one inline ingress block and no egress
# block, and Terraform's inline blocks are authoritative over the whole group - so rather than inheriting the
# allow-all egress EC2 attaches at creation, as the CloudFormation original did, the provider revoked it.
#
# A Fargate task needs outbound before its container exists: the agent fetches an ECR authorization token,
# pulls the image over HTTPS and opens a CloudWatch Logs stream, all through this interface. With egress
# revoked every task stops with ResourceInitializationError or CannotPullContainerError, the service keeps
# replacing them, and the apply itself reports success.
#
# All protocols to 0.0.0.0/0 rather than 443 only: this is also the path image pulls take, and ECR serves
# layers from S3 whose addresses are not a fixed set.
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.service.id
  description       = "ECR image pulls and CloudWatch Logs, direct to the internet from the public subnets"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_ecs_task_definition" "task_definition" {
  family                   = var.task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  # camelCase keys, which is what the ECS API documents. The _monolithic template's PascalCase keys were
  # accepted only because the provider's JSON decoding is case-insensitive.
  #
  # No taskRoleArn: nothing in this container calls an AWS API, and the _monolithic template did not set one
  # either. The execution role above is a different thing - it is assumed by the ECS agent before the
  # container exists, to pull the image and open the log stream.
  container_definitions = jsonencode([{
    name      = var.container_name
    image     = var.image_uri
    essential = true
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.task.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = var.log_stream_prefix
      }
    }
    portMappings = [{
      name          = "http"
      protocol      = "tcp"
      containerPort = var.container_port
    }]
  }])
  # The group's name is read off the resource above, so that reference already orders this after it. The
  # explicit edge keeps that true if the interpolation is ever changed to var.log_group_name, which would be
  # a literal with no edge - and the awslogs driver's response to a group that does not exist yet is to fail
  # the container start with a ResourceNotFoundException from CloudWatch Logs (rules.md D-1).
  depends_on = [aws_cloudwatch_log_group.task]
}
resource "aws_ecs_service" "service" {
  name            = var.service_name
  cluster         = var.cluster_name
  task_definition = aws_ecs_task_definition.task_definition.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = var.assign_public_ip
  }
  load_balancer {
    container_name   = var.container_name
    container_port   = var.container_port
    target_group_arn = var.target_group_arn
  }
  # CloudFormation holds an AWS::ECS::Service until it reaches a steady state before calling the resource
  # created; Terraform does not unless told to. True reproduces what the original stack did, and it is what
  # turns "the image does not serve on this port" into a failed apply rather than a green apply and an
  # empty target group.
  wait_for_steady_state = var.wait_for_steady_state
  # Two things the references above do not order this after (rules.md D-1):
  #   - the execution role's policy attachment, without which the first tasks cannot fetch an ECR token and
  #     stop before the container starts. The role ARN orders this after the role, not after its policies
  #   - the egress rule, for the same reason: the first pull leaves through it
  #
  # The _monolithic template also carried depends_on = [aws_lb, aws_lb_listener] here. Both of those live in
  # another module now, so the ordering is expressed by the caller's module-level depends_on instead
  # (rules.md D-2) - which also covers the load balancer's security group rules, as the original's
  # resource-level edges did not.
  depends_on = [
    aws_iam_role_policy_attachment.task_execution,
    aws_vpc_security_group_egress_rule.all_outbound,
  ]
}
