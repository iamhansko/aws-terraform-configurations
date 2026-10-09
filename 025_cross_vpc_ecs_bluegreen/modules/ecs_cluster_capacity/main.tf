# The ECS cluster and the EC2 capacity behind it, in one module because they are one decision: an
# Auto Scaling group is only a capacity provider once it is attached to a cluster, and the agent on
# each instance only joins the cluster whose name the launch template writes into its config.
#
# Fargate needs nothing from here. The red stack runs on Fargate, and the only trace of that in
# this module is FARGATE and FARGATE_SPOT appearing in the cluster's provider list below.
resource "aws_ecs_cluster" "ecs_cluster" {
  name = var.cluster_name
  setting {
    name  = "containerInsights"
    value = var.container_insights
  }
  # Only emitted when a key is supplied, which it is not by default. See the variable for why that
  # differs from the _monolithic template.
  dynamic "configuration" {
    for_each = var.managed_storage_kms_key_id == null ? [] : [var.managed_storage_kms_key_id]
    content {
      managed_storage_configuration {
        kms_key_id = configuration.value
      }
    }
  }
  tags = {
    Name = var.cluster_name
  }
}
resource "aws_security_group" "ecs_container_instance_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress blocks (rules.md F-2), and of the nine
# groups in this project this is the one where the missing egress rule is most immediately fatal.
#
# The _monolithic template gave this group a single inline ingress block - all traffic from the app
# VPC default group - and no egress block. CloudFormation leaves EC2's allow-all outbound rule
# alone when a template names only SecurityGroupIngress; Terraform's inline blocks are
# authoritative over the whole group and revoke it.
#
# A container instance with no outbound access cannot register with ECS at all. The agent calls
# ecs:RegisterContainerInstance over the private subnet's NAT gateway, that call times out, and
# the instance never appears in the cluster - so the cluster shows zero registered instances, the
# capacity provider has nothing to scale, and every task for the EC2-launch-type stack sits in
# PROVISIONING until the service gives up. Nothing in that chain mentions a security group.
#
# There is no inbound rule for the load balancer here on purpose: the task definitions use awsvpc,
# so a task gets its own interface and the ECS service security group guards it, not this one.
resource "aws_vpc_security_group_ingress_rule" "ecs_container_instance_all_traffic_source_group_ingress" {
  for_each = var.all_traffic_source_security_groups

  security_group_id            = aws_security_group.ecs_container_instance_security_group.id
  description                  = "All traffic from the ${each.key} security group"
  ip_protocol                  = "-1"
  referenced_security_group_id = each.value
}
resource "aws_vpc_security_group_egress_rule" "ecs_container_instance_egress" {
  security_group_id = aws_security_group.ecs_container_instance_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_iam_role" "ecs_container_instance_iam_role" {
  name_prefix = var.iam_role_name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ec2.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
# Both policies here stay exactly as the _monolithic template attached them, and rules.md A-5 is
# why rather than an exception to it.
#
# AmazonEC2ContainerServiceforEC2Role is the AWS service-role policy for a container instance -
# RegisterContainerInstance, Poll, SubmitTaskStateChange and the ECR read calls, nothing wider.
# AmazonSSMManagedInstanceCore is how a person gets a shell on an instance that has no inbound
# rule at all. Neither is a broad policy, so there is nothing to narrow; the roles this project
# does narrow are the task, execution, CodeDeploy, CodePipeline, EventBridge and flow log roles.
resource "aws_iam_role_policy_attachment" "ecs_container_instance_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.ecs_container_instance_iam_role.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "ecs_container_instance_profile" {
  name_prefix = var.iam_role_name_prefix
  # A single role name string, not the list CloudFormation's AWS::IAM::InstanceProfile Roles
  # property takes (rules.md A-3).
  role = aws_iam_role.ecs_container_instance_iam_role.name
}
resource "aws_launch_template" "ecs_launch_template" {
  name_prefix   = var.launch_template_name_prefix
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_container_instance_profile.name
  }
  vpc_security_group_ids = [aws_security_group.ecs_container_instance_security_group.id]
  # ECS_CLUSTER is the whole job of this script: the agent reads /etc/ecs/ecs.config at start and
  # joins the cluster named there. Get it wrong and the instance registers into "default" instead,
  # which exists in every account, so it registers successfully into the wrong place.
  #
  # The _monolithic template also ran "dnf install -y aws-cfn-bootstrap" here. There is no
  # CloudFormation stack to signal, nothing in the script calls cfn-signal, and the package is not
  # in the AL2023 repositories - so the line failed on every boot and the only thing it produced
  # was an error in the log for anyone diagnosing a real problem.
  user_data = base64encode(<<-EOT
    #!/bin/bash -xe
    echo ECS_CLUSTER=${aws_ecs_cluster.ecs_cluster.name} >> /etc/ecs/ecs.config
    %{for key, value in var.ecs_config_options~}
    echo ${key}=${value} >> /etc/ecs/ecs.config
    %{endfor~}
    EOT
  )
  metadata_options {
    http_endpoint = "enabled"
    # IMDSv2 required, as the _monolithic template had it. Worth knowing the consequence for a
    # container: a task reaching the instance metadata service has to do the token handshake, and
    # the default hop limit of 1 means a bridge-network container cannot reach it at all. The
    # task definitions here use awsvpc and take their credentials from the task role, so nothing
    # in this project depends on it.
    http_tokens = "required"
  }
  block_device_mappings {
    device_name = var.root_device_name
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = var.instance_name
    }
  }
  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = var.instance_name
    }
  }
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_autoscaling_group" "ecs_asg" {
  name_prefix         = var.auto_scaling_group_name_prefix
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = var.subnet_ids
  launch_template {
    id = aws_launch_template.ecs_launch_template.id
    # The template's own latest version, so a change to the user data or the AMI is picked up by
    # the next instance the group launches. $Latest would do the same without making the version
    # visible in a plan.
    version = aws_launch_template.ecs_launch_template.latest_version
  }
  availability_zone_distribution {
    capacity_distribution_strategy = var.capacity_distribution_strategy
  }
  # managed_termination_protection on the capacity provider below is DISABLED, which requires this
  # to be false. ECS validates the pair at CreateCapacityProvider and rejects the combination.
  protect_from_scale_in = false
  tag {
    key                 = "Name"
    value               = var.instance_name
    propagate_at_launch = true
  }
  # ECS writes this tag onto the group when the capacity provider below is attached, and managed
  # scaling uses it to recognise the instances it is responsible for. Declared here so the next
  # apply does not delete it - group tags are authoritative, so a tag Terraform does not know about
  # is removed. The value is empty because that is what ECS writes; declaring the same value keeps
  # the plan clean.
  tag {
    key                 = "AmazonECSManaged"
    value               = ""
    propagate_at_launch = true
  }
  # The cluster has to exist before an instance tries to join it. The launch template interpolates
  # the cluster name, which orders this after the cluster resource - this is the explicit edge the
  # _monolithic template also carried, kept because the interpolation is easy to refactor away
  # without noticing what it was holding up (rules.md D-1).
  depends_on = [aws_ecs_cluster.ecs_cluster]

  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_ecs_capacity_provider" "ecs_capacity_provider" {
  name = var.capacity_provider_name
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.arn
    # Instances are drained before termination, so a scale-in does not kill running tasks outright.
    managed_draining = "ENABLED"
    managed_scaling {
      status                    = var.managed_scaling_status
      target_capacity           = var.managed_scaling_target_capacity
      minimum_scaling_step_size = var.managed_scaling_minimum_step_size
      maximum_scaling_step_size = var.managed_scaling_maximum_step_size
      instance_warmup_period    = var.managed_scaling_instance_warmup_period
    }
    # DISABLED, as the _monolithic template had it. With it enabled ECS would hold an instance
    # running a task out of a scale-in, which is the safer production setting - and it also means
    # the Auto Scaling group cannot be deleted until ECS releases every instance, so a destroy can
    # sit for several minutes with no output.
    managed_termination_protection = "DISABLED"
  }

  lifecycle {
    create_before_destroy = true
  }
}
# FARGATE and FARGATE_SPOT are listed alongside the EC2 provider because the red stack runs on
# Fargate. A service that names launch_type = "FARGATE" does not strictly need the provider
# registered, but the default strategy below sends anything that names neither to the EC2
# provider, and having all three attached is what lets a task be moved between them by hand
# during a demo.
resource "aws_ecs_cluster_capacity_providers" "ecs_cluster_capacity_providers" {
  cluster_name       = aws_ecs_cluster.ecs_cluster.name
  capacity_providers = concat([aws_ecs_capacity_provider.ecs_capacity_provider.name], var.additional_capacity_providers)
  default_capacity_provider_strategy {
    base              = 0
    capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.name
    weight            = 100
  }
}
