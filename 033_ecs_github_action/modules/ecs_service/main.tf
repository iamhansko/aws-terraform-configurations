# The service, its task definition, the two task roles and the tasks' security group.
#
# The roles are here rather than in a module of their own because each is defined by what this task
# definition does with it: the execution role pulls this image and the task role is what these containers
# run as. Neither is shared with anything else (rules.md C-2).
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
resource "aws_iam_role" "task" {
  assume_role_policy = local.assume_ecs_tasks
}
resource "aws_iam_role" "task_execution" {
  assume_role_policy = local.assume_ecs_tasks
}
# One for_each attachment rather than the two numbered resources the conversion produced
# (aws_iam_role_policy_attachment.ecs_task_execution_iam_role_0 and _1) (rules.md B-7). toset is safe
# because the ARNs are literal strings in configuration and known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "task_execution" {
  for_each   = toset(var.task_execution_policy_arns)
  role       = aws_iam_role.task_execution.name
  policy_arn = each.value
}
resource "aws_iam_role_policy_attachment" "task" {
  for_each   = toset(var.task_policy_arns)
  role       = aws_iam_role.task.name
  policy_arn = each.value
}
# --- Security group for the task ENIs ---------------------------------------------------------------------
#
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2). The egress rule is the
# one the _monolithic template did not have: its group declared three ingress blocks and no egress block,
# and Terraform's inline rules are authoritative over the whole group, so the allow-all egress AWS puts on
# a new group was revoked. These are awsvpc ENIs in private subnets, so the pull goes out through a NAT
# gateway - with egress revoked every task stops with CannotPullContainerError before the container starts,
# and ECS keeps replacing them.
resource "aws_security_group" "service_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.service_security_group.id
  description       = "Image pulls and AWS API calls through the NAT gateway"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# Maps keyed by caller-chosen labels rather than lists, because the source IDs are other modules' outputs
# and unknown at plan time (rules.md B-8). each.key goes into the description so a plan shows which source
# each rule came from.
resource "aws_vpc_security_group_ingress_rule" "container_port_from_source" {
  for_each                     = var.container_port_ingress_source_security_groups
  security_group_id            = aws_security_group.service_security_group.id
  description                  = "Container port from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = each.value
}
# The _monolithic template's third ingress rule admitted all traffic from the VPC's default security group.
# Nothing here is launched into that group, so it admits nothing as built; it is reproduced because the
# original declared it, and the caller decides what goes in the map.
resource "aws_vpc_security_group_ingress_rule" "all_traffic_from_source" {
  for_each                     = var.all_traffic_ingress_source_security_groups
  security_group_id            = aws_security_group.service_security_group.id
  description                  = "All traffic from the ${each.key} security group"
  ip_protocol                  = "-1"
  referenced_security_group_id = each.value
}
# --- Task definition --------------------------------------------------------------------------------------
resource "aws_ecs_task_definition" "task_definition" {
  family                   = var.task_family
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  network_mode             = "awsvpc"
  requires_compatibilities = var.requires_compatibilities
  task_role_arn            = aws_iam_role.task.arn
  execution_role_arn       = aws_iam_role.task_execution.arn
  runtime_platform {
    cpu_architecture        = var.cpu_architecture
    operating_system_family = var.operating_system_family
  }
  # camelCase keys, which is what the ECS API documents. The _monolithic template's PascalCase keys were
  # accepted only because the provider's JSON decoding is case-insensitive.
  #
  # image carries the tag. The original passed the repository URL with no tag at all, which docker resolves
  # to :latest - the same image the workbench pushes, so it worked, but by accident rather than by saying
  # so. This takes the full reference the repository module assembles, so the push and the pull are one
  # value (rules.md B-5).
  #
  # No logConfiguration, as the original had none: container output stays on the container instance under
  # the default json-file driver rather than reaching CloudWatch. Worth knowing before trying to read a
  # crash loop from the console.
  container_definitions = jsonencode([{
    name      = var.container_name
    image     = var.container_image
    essential = true
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
      interval    = var.health_check_interval
      retries     = var.health_check_retries
      startPeriod = var.health_check_start_period
      timeout     = var.health_check_timeout
    }
    portMappings = [{
      name          = "http"
      protocol      = "tcp"
      containerPort = var.container_port
      # With awsvpc the host port has to equal the container port or be omitted, so this is the container
      # port by definition rather than a second choice.
      hostPort = var.container_port
    }]
  }])
}
# --- Service ----------------------------------------------------------------------------------------------
resource "aws_ecs_service" "service" {
  # CloudFormation generated this name; Terraform requires one, so the caller derives it. The GitHub
  # Actions workflow and the CodeDeploy deployment group both name this service, so all three read it from
  # one place (rules.md B-5).
  name            = var.name
  cluster         = var.cluster_name
  task_definition = aws_ecs_task_definition.task_definition.arn
  desired_count   = var.desired_count
  launch_type     = var.launch_type
  # CODE_DEPLOY, which is what makes the rest of this project necessary: with the default ECS controller
  # there would be one target group and no CodeDeploy application at all. ECS validates the shape at
  # CreateService and requires exactly one load_balancer block naming the group that is live to begin with.
  deployment_controller {
    type = "CODE_DEPLOY"
  }
  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.service_security_group.id]
    assign_public_ip = false
  }
  load_balancer {
    container_name   = var.container_name
    container_port   = var.container_port
    target_group_arn = var.target_group_arn
  }
  wait_for_steady_state = var.wait_for_steady_state

  lifecycle {
    # The two fields CodeDeploy owns once the first deployment has run.
    #
    # Every deployment registers a new task definition revision, moves the service onto it, and swaps the
    # target group in the service's load balancer configuration. Terraform recorded the revision it created
    # and the blue group, so without this every plan after a deployment proposes rolling the service back
    # to both - and applying it undoes the deployment while CodeDeploy still reports it as succeeded.
    #
    # launch_type and capacity_provider_strategy are the other pair CodeDeploy takes over, and the first
    # deployment is what does it. The workflow's appspec places the replacement task set with a
    # CapacityProviderStrategy - this project's EC2 provider, or FARGATE on the Fargate branch - so once it
    # has run, ECS reports launchType null and a capacity provider strategy on the service. Tracked, that
    # breaks every plan from then on in two ways at once: the provider rejects the strategy change with
    # "force_new_deployment should be true when capacity_provider_strategy is being updated", and behind
    # that error launch_type going from EC2 to null is a forced replacement of the service. launch_type
    # still applies at creation, which is what places the first task set on the container instances.
    #
    # This is rules.md E-8's argument with one difference that matters: there the advice is to exclude the
    # single path rather than freeze the whole object, and here each of these already is a single
    # attribute, so naming them is as narrow as it gets. desired_count, the subnets and the security group
    # stay tracked.
    ignore_changes = [task_definition, load_balancer, launch_type, capacity_provider_strategy]
  }

  # Two things no value reference orders this after (rules.md D-1):
  #   - the execution role's policy, which ECS checks when the first task starts; without it the task stops
  #     with a pull failure that names the role rather than the policy
  #   - the egress rule, without which the first tasks cannot pull at all
  #
  # The listener is the third edge the _monolithic template carried here, and it is not expressible from
  # inside this module - target_group_arn orders this after one target group and nothing else. The root
  # orders this module after the whole load balancer module instead (rules.md D-2).
  depends_on = [
    aws_iam_role_policy_attachment.task_execution,
    aws_vpc_security_group_egress_rule.all_outbound,
  ]
}
