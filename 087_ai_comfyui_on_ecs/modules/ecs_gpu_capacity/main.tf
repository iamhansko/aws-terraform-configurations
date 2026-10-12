# The blueprint's AsgConstruct and the capacity half of its EcsConstruct: the GPU instance's security group,
# role and launch template, the Auto Scaling group of at most one spot GPU instance, the scale-in-when-idle
# alarm and the optional work-hour schedule, and the ECS capacity provider that hands the group to the
# cluster.
resource "aws_security_group" "instance" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# All outbound and nothing inbound, as the blueprint had it. The task runs in awsvpc mode with a network
# interface and a security group of its own, so the load balancer never talks to the instance's address.
resource "aws_vpc_security_group_egress_rule" "instance_all" {
  security_group_id = aws_security_group.instance.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# --- Instance role --------------------------------------------------------------------------------------

resource "aws_iam_role" "instance" {
  name_prefix = "${substr(var.name, 0, 28)}-host-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
# The blueprint's managed policies. toset is safe because the ARNs are literal strings in configuration
# (rules.md B-7/B-8). See instance_policy_arns for why AmazonEC2FullAccess is kept.
resource "aws_iam_role_policy_attachment" "instance" {
  for_each   = toset(var.instance_policy_arns)
  role       = aws_iam_role.instance.name
  policy_arn = each.value
}
# What CDK's cluster.add_asg_capacity_provider added to the instance role so the ECS agent can register with
# this cluster and no other - the same statements, scoped the same way.
resource "aws_iam_role_policy" "ecs_agent" {
  name = "ecs-agent"
  role = aws_iam_role.instance.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecs:DeregisterContainerInstance", "ecs:RegisterContainerInstance", "ecs:Submit*"]
        Resource = var.cluster_arn
      },
      {
        Effect   = "Allow"
        Action   = ["ecs:Poll", "ecs:StartTelemetrySession"]
        Resource = "*"
        Condition = {
          ArnEquals = { "ecs:cluster" = var.cluster_arn }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken", "ecs:DiscoverPollEndpoint", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
    ]
  })
}
resource "aws_iam_instance_profile" "instance" {
  # A single role name, not the list CloudFormation's InstanceProfile takes (rules.md A-3).
  role = aws_iam_role.instance.name
}

# --- Launch template ------------------------------------------------------------------------------------

locals {
  # The blueprint's user data, then the lines CDK's add_asg_capacity_provider appended to it.
  #
  # The blueprint's three commands install the REX-Ray EBS volume plugin, which is what gives the task a
  # 250 GiB gp3 EBS volume that outlives the instance it is attached to (modules/comfyui_service). The one
  # change is where the region comes from: the blueprint read it from the instance metadata with an IMDSv1
  # call, which fails on an account whose instance metadata defaults require tokens; it is written in from
  # Terraform here instead (rules.md B-5).
  #
  # CDK's lines join the cluster and keep containers away from the instance role: the iptables rule drops
  # bridge-network traffic to the metadata address and ECS_AWSVPC_BLOCK_IMDS does the same for awsvpc tasks,
  # the blueprint's mode. That matters here more than usual, because the instance role carries
  # AmazonEC2FullAccess.
  user_data = <<-EOT
    #!/bin/bash
    docker plugin install ${var.docker_volume_plugin} --grant-all-permissions REXRAY_PREEMPT=true EBS_REGION=${var.region}
    systemctl restart docker
    echo ECS_CLUSTER=${var.cluster_name} >> /etc/ecs/ecs.config
    sudo iptables --insert FORWARD 1 --in-interface docker+ --destination 169.254.169.254/32 --jump DROP
    sudo service iptables save
    echo ECS_AWSVPC_BLOCK_IMDS=true >> /etc/ecs/ecs.config
    EOT
}
resource "aws_launch_template" "instance" {
  name_prefix            = "${var.name}-"
  image_id               = var.ami_id
  vpc_security_group_ids = [aws_security_group.instance.id]
  user_data              = base64encode(local.user_data)
  # So the console and describe-launch-templates show the version the group launches from.
  update_default_version = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }

  # 50 GiB and encrypted, as the blueprint's block device. No volume_type, as it set none: EC2 then takes the
  # AMI's, gp2 for the ECS GPU AMI. ComfyUI itself, its models and its outputs are on the separate REX-Ray
  # volume, not here.
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = var.root_volume_size
      encrypted   = "true"
    }
  }

  # No metadata_options, as the blueprint had none. The REX-Ray plugin calls the instance metadata service
  # from inside its own container, with an AWS SDK of a version this configuration cannot see, so neither a
  # token requirement nor a hop limit is imposed on it here.

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = var.name
    }
  }
  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = var.name
    }
  }
  tags = {
    Name = var.name
  }

  # The ECS agent registers within seconds of boot, and without its policy in place that call is denied and
  # the instance never joins. The instance profile ARN does not order this after the policies (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.instance, aws_iam_role_policy.ecs_agent]
}

# --- Auto Scaling group ---------------------------------------------------------------------------------

resource "aws_autoscaling_group" "instance" {
  name_prefix           = "${var.name}-"
  min_size              = var.min_size
  max_size              = var.max_size
  desired_capacity      = var.desired_capacity
  vpc_zone_identifier   = var.subnet_ids
  protect_from_scale_in = false

  # Not waiting for the instance, as CloudFormation did not. A GPU instance takes minutes to boot and spot
  # capacity may not be there at all, and with desired_capacity set the provider would otherwise wait for it
  # and fail the apply after ten minutes - while the group keeps trying on its own.
  wait_for_capacity_timeout = "0"
  # Deletes the group without waiting out its lifecycle hooks. ECS managed draining puts one on it, and on
  # destroy the service is already gone by the time the group is deleted, so there is nothing left to drain.
  force_delete = true

  # The blueprint's MixedInstancesPolicy: spot only (or on-demand only), the cheapest of the listed types that
  # has capacity, never above spot_max_price.
  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = var.use_spot ? 0 : 100
      on_demand_allocation_strategy            = "lowest-price"
      spot_allocation_strategy                 = "lowest-price"
      spot_instance_pools                      = 1
      spot_max_price                           = var.spot_max_price
    }
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.instance.id
        version            = aws_launch_template.instance.latest_version
      }
      dynamic "override" {
        for_each = var.instance_types
        content {
          instance_type = override.value
        }
      }
    }
  }

  # ECS writes this tag onto the group when the capacity provider below is created - with managed scaling off
  # too - with an empty value and propagate_at_launch on. Declared so it is Terraform's as well: without it
  # the next plan proposes removing it. The empty value is what ECS writes, so the two agree from the start.
  tag {
    key                 = "AmazonECSManaged"
    value               = ""
    propagate_at_launch = true
  }

  lifecycle {
    # desired_capacity has other owners once the group exists, which is the blueprint's whole cost model: the
    # idle alarm below takes it to zero after an hour without work, the admin page's scale-up and shutdown
    # set it to one and zero, and the optional schedule does both. Without this every plan after one of those
    # proposes putting the instance back - or taking it away. Only this field is ignored (rules.md E-8).
    ignore_changes = [desired_capacity]
  }

  depends_on = [aws_iam_role_policy_attachment.instance, aws_iam_role_policy.ecs_agent]
}
# The blueprint's auto_scale_down: average CPU under 1% for sixty consecutive minutes takes the group down
# by one, which with a maximum of one is to zero. The admin page brings it back.
resource "aws_autoscaling_policy" "scale_in_when_idle" {
  count = var.auto_scale_down ? 1 : 0

  name                   = "${var.name}-scale-in-when-idle"
  autoscaling_group_name = aws_autoscaling_group.instance.name
  policy_type            = "StepScaling"
  adjustment_type        = "ChangeInCapacity"
  # Bounds relative to the alarm threshold, as CDK's low-level StepScalingAction wrote them. Any breach of a
  # less-than alarm is below the threshold and lands in the first step; the second only closes the range.
  step_adjustment {
    scaling_adjustment          = -1
    metric_interval_upper_bound = "1"
  }
  step_adjustment {
    scaling_adjustment          = 0
    metric_interval_lower_bound = "1"
  }
  # No cooldown, though the blueprint passed one: it is valid only for simple scaling, and CDK dropped it from
  # the template with a warning.
}
resource "aws_cloudwatch_metric_alarm" "idle" {
  count = var.auto_scale_down ? 1 : 0

  alarm_name          = "${var.name}-idle"
  alarm_description   = "Scales the ComfyUI GPU instance in after ${var.idle_minutes} minutes below ${var.idle_cpu_threshold_percent}% CPU"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = var.idle_minutes
  datapoints_to_alarm = var.idle_minutes
  comparison_operator = "LessThanThreshold"
  threshold           = var.idle_cpu_threshold_percent
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.instance.name
  }
  alarm_actions = [aws_autoscaling_policy.scale_in_when_idle[0].arn]
}
# The blueprint's schedule_auto_scaling: down after work, up at the start of it. Desired capacity only -
# min_size and max_size are -1, which leaves them alone, where the provider's default of 0 would set the
# maximum to zero and keep the morning scale-up from launching anything.
resource "aws_autoscaling_schedule" "scale_down" {
  count = var.schedule_auto_scaling ? 1 : 0

  scheduled_action_name  = "${var.name}-after-work-hours"
  autoscaling_group_name = aws_autoscaling_group.instance.name
  recurrence             = var.schedule_scale_down
  time_zone              = var.schedule_timezone
  desired_capacity       = 0
  min_size               = -1
  max_size               = -1
}
resource "aws_autoscaling_schedule" "scale_up" {
  count = var.schedule_auto_scaling ? 1 : 0

  scheduled_action_name  = "${var.name}-start-work-hours"
  autoscaling_group_name = aws_autoscaling_group.instance.name
  recurrence             = var.schedule_scale_up
  time_zone              = var.schedule_timezone
  desired_capacity       = 1
  min_size               = -1
  max_size               = -1
}

# --- Capacity provider ----------------------------------------------------------------------------------

# Not converted: the drain hook CDK attached to the group - a termination lifecycle hook, an SNS topic and a
# python3.9 Lambda that set the container instance to DRAINING and waited for its tasks to stop. CDK adds it
# whenever a capacity provider leaves managed draining unset, as the blueprint's did, and ECS turns managed
# draining on by default for a new capacity provider - so the blueprint ran both. Managed draining is set
# explicitly below and does the same job, and its own lifecycle hook is also what produces the
# "EC2 Instance-terminate Lifecycle Action" event the admin functions' scale-in listener waits for. The python3.9
# runtime CDK 2.150 gave that function has also been out of Lambda support since December 2025.
resource "aws_ecs_capacity_provider" "gpu" {
  name = var.capacity_provider_name

  auto_scaling_group_provider {
    # The ARN rather than the name. ECS accepts either and stores the ARN, so a name here would read back as
    # a difference on a field that forces replacement - which ECS refuses while the cluster names the provider.
    auto_scaling_group_arn         = aws_autoscaling_group.instance.arn
    managed_termination_protection = "DISABLED"
    managed_draining               = "ENABLED"
    # Off, as the blueprint's enable_managed_scaling=False. On, ECS would put a target tracking policy on the
    # group and own desired_capacity - which the idle alarm, the admin page and the schedule already share.
    managed_scaling {
      status = "DISABLED"
    }
  }
}
# A separate resource rather than part of the cluster, which is what keeps the graph acyclic: the instances
# need the cluster name, and the cluster association needs the group's provider. No default strategy, as the
# blueprint's DefaultCapacityProviderStrategy was empty - the service names the provider itself.
resource "aws_ecs_cluster_capacity_providers" "cluster" {
  cluster_name       = var.cluster_name
  capacity_providers = [aws_ecs_capacity_provider.gpu.name]
}
