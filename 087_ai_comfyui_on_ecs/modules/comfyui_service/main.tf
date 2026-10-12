# The workload half of the blueprint's EcsConstruct: the task's role and log group, the task definition with
# its REX-Ray volume, the service's security group, and the ECS service on the GPU capacity provider.
resource "aws_cloudwatch_log_group" "comfyui" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
}
# One role as both the task role and the execution role, as the blueprint used it. ComfyUI makes no AWS calls
# of its own, so the role's only job is the agent's: pulling the image and writing the log.
resource "aws_iam_role" "task" {
  name_prefix = "${substr(var.name, 0, 32)}-task-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
# The blueprint's managed policy. CDK also added an inline policy granting the same ECR pull and log actions on
# the asset repository and the log group, which this policy already grants everywhere; it is not repeated.
resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task.name
  policy_arn = "arn:${var.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_ecs_task_definition" "comfyui" {
  family                   = var.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  task_role_arn            = aws_iam_role.task.arn
  execution_role_arn       = aws_iam_role.task.arn

  # Where ComfyUI lives, mounted over its own install directory: the blueprint's shared, autoprovisioned
  # REX-Ray volume. On first use the plugin creates a gp3 EBS volume of this size, Docker copies the image's
  # /home/user/opt/ComfyUI into it, and from then on ComfyUI's code, its custom nodes, the models downloaded
  # through the Manager and every output live on that volume, whichever instance the task lands on.
  #
  # That volume is not a Terraform resource - the plugin creates it at runtime, in the zone of the first
  # instance that runs the task - so terraform destroy leaves it behind, as deleting the blueprint's stack did.
  # The root's comfyui_volume_command output finds it. Being an EBS volume it is tied to that zone, so a later
  # instance launched in the other zone cannot attach it.
  volume {
    name = var.volume_name
    docker_volume_configuration {
      scope         = "shared"
      autoprovision = true
      driver        = var.volume_driver
      driver_opts = {
        volumetype = var.volume_type
        size       = tostring(var.volume_size_gib)
      }
    }
  }

  container_definitions = jsonencode([{
    name      = var.container_name
    image     = var.image
    essential = true
    # A soft limit only, as the blueprint sized it: 90% of the smallest instance type's memory, so the task
    # still places on any of them.
    memoryReservation = var.memory_reservation_mib
    resourceRequirements = [{
      type  = "GPU"
      value = tostring(var.gpu_count)
    }]
    linuxParameters = {
      maxSwap    = var.max_swap_mib
      swappiness = var.swappiness
    }
    portMappings = [{
      name          = "comfyui-port-mapping"
      containerPort = var.container_port
      hostPort      = var.container_port
      protocol      = "tcp"
      appProtocol   = "http"
    }]
    mountPoints = [{
      sourceVolume  = var.volume_name
      containerPath = var.mount_path
      readOnly      = false
    }]
    # Sorted by name, which is how ECS returns them, so the next plan does not read a reordering as a change.
    environment = [for name in sort(keys(var.environment)) : { name = name, value = var.environment[name] }]
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/system_stats || exit 1"]
      interval    = 15
      timeout     = 10
      retries     = 8
      startPeriod = 30
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.comfyui.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = var.log_stream_prefix
      }
    }
  }])
}
resource "aws_security_group" "service" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
resource "aws_vpc_security_group_egress_rule" "service_all" {
  security_group_id = aws_security_group.service.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# The container port from the load balancer. A map with literal keys, because the IDs are another module's
# outputs and unknown at plan (rules.md B-8). The blueprint declared this rule twice, once on the group and
# once more through the target group's connection; EC2 holds one rule per source and port, so it is here once.
resource "aws_vpc_security_group_ingress_rule" "from_sources" {
  for_each = var.ingress_source_security_groups

  security_group_id            = aws_security_group.service.id
  description                  = "ComfyUI port from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = each.value
}
resource "aws_ecs_service" "comfyui" {
  name                = var.name
  cluster             = var.cluster_arn
  task_definition     = aws_ecs_task_definition.comfyui.arn
  desired_count       = var.desired_count
  scheduling_strategy = "REPLICA"
  # The blueprint's deployment settings. With one GPU per instance and one instance, a second copy of the task
  # has nowhere to go, so a deployment stops the old task first rather than waiting for room.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  enable_ecs_managed_tags            = false

  # No launch_type: it and a capacity provider strategy are mutually exclusive.
  capacity_provider_strategy {
    capacity_provider = var.capacity_provider_name
    weight            = 1
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  # No wait_for_steady_state, and deliberately so: the task places only once the Auto Scaling group has a GPU
  # instance registered, which depends on spot capacity for one of the listed types - and on the account having
  # a non-zero quota for G instances, which a new account does not. Waiting would hang the apply on that
  # rather than report it, and service_events_command in the outputs is where the reason appears.

  # The first task pulls the image with the role's policy and has to be reachable from the load balancer, and
  # neither the task definition's role ARN nor the security group ID implies those (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.task_execution,
    aws_vpc_security_group_ingress_rule.from_sources,
    aws_vpc_security_group_egress_rule.service_all,
  ]
}
