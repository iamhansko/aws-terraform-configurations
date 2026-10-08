# No data sources in this module. The awslogs region arrives as var.region from the root - see that
# variable for why reading it here was not harmless (rules.md D-6).
resource "aws_cloudwatch_log_group" "ecs_task_log_group" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_in_days
}
# Two roles, and the distinction between them is the one most worth getting right here.
#
# The task role is assumed by the process inside the container. The execution role is assumed by the ECS
# agent on the task's behalf, before the container exists, to pull the image and open the log stream.
# Both are trusted by ecs-tasks.amazonaws.com, which is why they look identical and why swapping their
# policies produces a task that either cannot start or starts without the permissions it expected.
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
# for_each over the list rather than one attachment per policy (rules.md B-7). toset is safe because
# these are literal strings in configuration and known at plan time (rules.md B-8). The list can be
# empty, which for the task role is the accurate configuration - see the variable.
resource "aws_iam_role_policy_attachment" "ecs_task_role" {
  for_each   = toset(var.task_role_policy_arns)
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
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family             = var.task_family
  task_role_arn      = aws_iam_role.ecs_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  network_mode       = var.network_mode
  cpu                = var.task_cpu
  memory             = var.task_memory
  # The point of the project. A host volume is a bind mount: the container gets a directory that belongs
  # to the instance, so what it writes survives the task and is visible to anything else on that
  # instance - and is lost when the instance goes, which on an entirely spot Auto Scaling group is a
  # thing that happens without notice. The alternative shapes, for contrast, are an empty docker volume
  # (gone with the task), an EBS volume configured at launch (one per task, needs the ECS infrastructure
  # role the task_role_policy_arns variable describes) and EFS (shared across instances).
  volume {
    name      = var.volume_name
    host_path = var.host_volume_path
  }
  container_definitions = jsonencode([{
    Name      = var.container_name
    Image     = var.image_uri
    Essential = true
    LogConfiguration = {
      LogDriver = "awslogs"
      Options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs_task_log_group.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = var.log_stream_prefix
      }
    }
    MountPoints = [{
      ContainerPath = var.container_mount_path
      SourceVolume  = var.volume_name
      ReadOnly      = var.read_only_volume
    }]
  }])

  # The log group is named as a string inside container_definitions, so the reference above does order
  # this after it - but only because the name is read from the resource rather than from the variable.
  # Written as var.log_group_name it would be a literal with no edge, and the first task could then open
  # a stream in a group that does not exist yet; the awslogs driver's response to that is to fail the
  # container start with a ResourceNotFoundException from CloudWatch Logs (rules.md D-1). The explicit
  # dependency keeps that true even if the interpolation above is changed.
  depends_on = [aws_cloudwatch_log_group.ecs_task_log_group]
}
# The service, which is what keeps desired_count copies of the task running.
#
# The _monolithic template gave this resource depends_on = [aws_cloudwatch_log_group...] and gave the
# task definition depends_on = [aws_instance.ec2]. The second one was the interesting one and it does not
# survive the translation: in CloudFormation the Ec2 resource carried a CreationPolicy waiting for
# cfn-signal, so "after the instance" meant "after the image had been built and pushed". In Terraform the
# instance resource completes when RunInstances returns and the instance is running, which is before
# cloud-init has installed docker - so the ordering it bought is gone. The conversion's own comment notes
# the CreationPolicy is not reproduced; what it does not note is that this depends_on was load-bearing
# because of it.
#
# The replacement is in the root: the builder writes a marker file at the end of its userdata, an SSM
# association waits for that marker and then confirms the image is actually in the repository, and the
# caller orders this module after that association. This module deliberately knows none of that - it
# takes an image reference and is ordered by its caller (rules.md D-2).
resource "aws_ecs_service" "ecs_service" {
  name                = var.service_name
  cluster             = var.cluster_name
  task_definition     = aws_ecs_task_definition.ecs_task_definition.arn
  desired_count       = var.desired_count
  scheduling_strategy = var.scheduling_strategy
  # No launch_type, which is not an omission: launch_type and capacity_provider_strategy are mutually
  # exclusive, and setting both fails at apply.
  capacity_provider_strategy {
    # The name, not the ARN. The _monolithic template wrote aws_ecs_capacity_provider.x.id here, and that
    # resource's id is its ARN - ECS documents this field as the provider's short name and returns the
    # name, so an ARN leaves a difference between configuration and state that never settles. The
    # ecs_asg_capacity_provider module makes the same correction in the cluster association.
    capacity_provider = var.capacity_provider_name
    base              = var.capacity_provider_base
    weight            = var.capacity_provider_weight
  }
  enable_ecs_managed_tags = var.enable_ecs_managed_tags
  # Written out even when disabled: turning Service Connect off on a service that had it on requires an
  # explicitly disabled block, because an absent block leaves the existing configuration untouched.
  service_connect_configuration {
    enabled = var.enable_service_connect
  }
  # Ordered, and the order is the meaning: ECS applies these in sequence, so zones are balanced first and
  # only then are instances within a zone. Reversing them would fill one zone's instances before using
  # the other zone at all.
  ordered_placement_strategy {
    field = "attribute:ecs.availability-zone"
    type  = "spread"
  }
  # The strategy that keeps two tasks off one instance while spare instances exist. With host networking
  # and a bind mount, two tasks on one instance share the host directory and both write into it - which
  # is a legitimate thing to demonstrate, but not what this configuration is showing.
  ordered_placement_strategy {
    field = "instanceId"
    type  = "spread"
  }
  wait_for_steady_state = var.wait_for_steady_state
}
