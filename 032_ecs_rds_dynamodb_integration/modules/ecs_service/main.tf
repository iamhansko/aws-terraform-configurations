# The region the awslogs driver is told to write to. The one data source in this module.
#
# The caller declares this module with depends_on, which defers every data source inside it to apply
# (rules.md D-6). Harmless for this one: the value becomes a string inside container_definitions, not a
# resource address and not a for_each or count key, so nothing needs it at plan time. A data source whose
# result shaped an address would have to be lifted into the root instead.
data "aws_region" "current" {}
# The log group, which the _monolithic template did not have.
#
# Its three container definitions declared no LogConfiguration at all, so the containers logged to the
# instance's local json-file driver and nothing read it. For these three applications that is the difference
# between a diagnosable demo and a guess: gin writes one line per request, and the user application's
# database errors and the product application's DynamoDB errors are returned to the caller as a bare
# "Internal Server Error" with the real reason only in the container's own output.
#
# This is an addition rather than a reproduction. It needs no extra permissions: the log stream is opened by
# the agent with the execution role, whose AmazonECSTaskExecutionRolePolicy already allows it.
resource "aws_cloudwatch_log_group" "ecs_task_log_group" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_in_days
}
locals {
  # Environment and secrets as sorted lists, built from maps.
  #
  # Maps in the module interface and lists in the API payload. The sort is what keeps the payload stable:
  # jsonencode of an unsorted list would reorder on nothing, and container_definitions is compared as a
  # string, so every plan would propose a new task definition revision and every apply would redeploy all
  # three services.
  #
  # The split between the two is the point of this pair. environment entries are stored in the task
  # definition in plaintext and are readable by anyone who can call ecs:DescribeTaskDefinition, permanently,
  # in every revision. secrets entries store only a reference; the agent resolves it with the execution role
  # just before the container starts. The _monolithic template put the database password in the first list.
  environment = [for key in sort(keys(var.environment)) : {
    Name  = key
    Value = var.environment[key]
  }]
  secrets = [for key in sort(keys(var.secrets)) : {
    Name      = key
    ValueFrom = var.secrets[key]
  }]
}
resource "aws_ecs_task_definition" "ecs_task_definition" {
  # One family per application. The template gave all three task definitions family = "user-taskdef", which
  # is not a name collision error - ECS would accept it and register three revisions of one family, each
  # overwriting the previous one's place in the console and in "describe-task-definition <family>". Each
  # service would still run the exact revision ARN Terraform handed it, so it worked; what it destroyed was
  # the ability to tell the three apart afterwards, and "aws ecs describe-task-definition user-taskdef"
  # would return whichever of the three was registered last.
  family             = var.task_family
  cpu                = var.task_cpu
  memory             = var.task_memory
  task_role_arn      = var.task_role_arn
  execution_role_arn = var.execution_role_arn
  # awsvpc on the EC2 launch type, as the template had it. Each task gets its own ENI in the service
  # security group, which is what lets the database admit the tasks by security group rather than by subnet,
  # and it is also what caps two tasks per t3.medium - see modules/ecs_asg_capacity_provider.
  network_mode             = var.network_mode
  requires_compatibilities = var.requires_compatibilities
  runtime_platform {
    cpu_architecture        = var.cpu_architecture
    operating_system_family = var.operating_system_family
  }
  container_definitions = jsonencode([{
    Name      = var.container_name
    Image     = var.image_uri
    Essential = true
    # A genuine list of maps, unlike the shape rules.md A-3 warns about: container_definitions takes a JSON
    # array of container objects, so jsonencode([...]) here is correct rather than a CloudFormation list
    # property squeezed into a scalar attribute.
    PortMappings = [{
      ContainerPort = var.container_port
      HostPort      = var.container_port
      Name          = var.port_mapping_name
    }]
    Environment = local.environment
    Secrets     = local.secrets
    HealthCheck = {
      Command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
      Interval    = var.health_check_interval
      Retries     = var.health_check_retries
      Timeout     = var.health_check_timeout
      StartPeriod = var.health_check_start_period
    }
    LogConfiguration = {
      LogDriver = "awslogs"
      Options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs_task_log_group.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = var.log_stream_prefix
      }
    }
  }])
  # The log group's name is interpolated above from the resource rather than from the variable, which does
  # create the edge - but only because of where it is read from. Written as var.log_group_name it would be a
  # literal with no dependency, and the first task could then open a stream in a group that does not exist
  # yet; the awslogs driver answers that by failing the container start with a ResourceNotFoundException
  # from CloudWatch Logs (rules.md D-1). Stated explicitly so it stays true if that interpolation changes.
  #
  # The template's depends_on here was [aws_instance.bastion_ec2], and that one does not survive the
  # translation. In CloudFormation the bastion carried a CreationPolicy waiting for cfn-signal, so "after
  # the bastion" meant "after the images had been built and pushed". In Terraform an aws_instance completes
  # when the instance is running, which is minutes before cloud-init has installed docker - so the ordering
  # it bought is gone, and the replacement is in the root: the build associations write marker files and the
  # caller orders this module after them (rules.md D-5).
  depends_on = [aws_cloudwatch_log_group.ecs_task_log_group]
}
resource "aws_ecs_service" "ecs_service" {
  name            = var.service_name
  cluster         = var.cluster_name
  task_definition = aws_ecs_task_definition.ecs_task_definition.arn
  desired_count   = var.desired_count
  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }
  # No launch_type, where the template wrote launch_type = "EC2".
  #
  # The two are mutually exclusive and setting both fails at apply, so this is a change rather than an
  # addition, and it is a small behavioural one. launch_type = "EC2" places tasks on container instances and
  # works - but it bypasses the cluster's capacity provider entirely, so the tasks do not count toward the
  # provider's target capacity and ECS managed scaling, which the template enabled, sees nothing to scale
  # for. Naming the provider is what makes the capacity provider in this project mean something.
  #
  # The name, not the ARN. The template wrote aws_ecs_capacity_provider.x.id in the cluster association and
  # that resource's id is its ARN; ECS documents this field as the provider's short name and returns the
  # name, so an ARN leaves a difference between configuration and state that never settles.
  capacity_provider_strategy {
    capacity_provider = var.capacity_provider_name
    base              = var.capacity_provider_base
    weight            = var.capacity_provider_weight
  }
  enable_execute_command = var.enable_execute_command
  # Ordered, and the order is the meaning: ECS applies these in sequence, so zones are balanced first and
  # only then instances within a zone. Reversed, one zone's instances would fill before the other zone is
  # used at all - which for three single-task services would put all three in one Availability Zone.
  ordered_placement_strategy {
    field = "attribute:ecs.availability-zone"
    type  = "spread"
  }
  ordered_placement_strategy {
    field = "instanceId"
    type  = "spread"
  }
  wait_for_steady_state = var.wait_for_steady_state
}
