resource "aws_security_group" "container_instance_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2), and the egress rule
# is the same fix the other three groups in this project describe - this group had the same hole.
#
# The _monolithic template gave it one inline ingress block for SSH from the bastion and no egress
# block. CloudFormation leaves the allow-all outbound rule EC2 adds at creation in place when a template
# names only SecurityGroupIngress; Terraform's inline blocks are authoritative over the whole group, so
# declaring one revokes it.
#
# What that costs here is the entire cluster, and in a way that produces no error message anywhere.
# These instances are in private subnets, so every outbound call goes through a NAT gateway: the ECS
# agent calling RegisterContainerInstance against ecs.<region>.amazonaws.com, the long poll it holds
# open waiting for task assignments, the ECR authorization token and the image layers. With egress
# revoked none of it leaves the instance. The instances come up healthy in the Auto Scaling group and
# the cluster reports zero registered container instances - because an instance that never registers
# never becomes an ECS object that could report a problem. The service then says it was unable to place
# a task because no container instance met its requirements, which points at placement constraints.
resource "aws_vpc_security_group_egress_rule" "container_instance_egress" {
  security_group_id = aws_security_group.container_instance_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# SSH from the bastion, which is what the _monolithic template's one inline rule was. A map keyed by a
# caller-chosen label rather than a list, because the bastion's group ID is another module's output and
# unknown at plan time (rules.md B-8). each.key goes into the description so a plan shows where the rule
# came from.
resource "aws_vpc_security_group_ingress_rule" "container_instance_ssh_ingress" {
  for_each = var.ssh_ingress_source_security_groups

  security_group_id            = aws_security_group.container_instance_security_group.id
  description                  = "SSH from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.ssh_port
  to_port                      = var.ssh_port
  referenced_security_group_id = each.value
}
# Nothing in this project needs to reach the instances on the container port - the tasks use awsvpc, so
# the load balancer connects to the task's own interface and this group is not in that path at all. The
# hook exists for a caller that changes the network mode to bridge, where it would be required.
resource "aws_vpc_security_group_ingress_rule" "container_instance_source_group_ingress" {
  for_each = var.ingress_source_security_groups

  security_group_id            = aws_security_group.container_instance_security_group.id
  description                  = "All traffic from the ${each.key} security group"
  ip_protocol                  = "-1"
  referenced_security_group_id = each.value
}
resource "aws_iam_role" "container_instance_iam_role" {
  # A generated name, where the _monolithic template used the fixed "EcsAutoScalingGroupIamRole". IAM
  # role names are account-wide, so the fixed one makes a second copy of this project fail at apply with
  # EntityAlreadyExists - and worse, makes it look like it might succeed by attaching to the first
  # copy's role.
  name_prefix = var.role_name_prefix
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
# One for_each attachment rather than the two numbered resources the conversion produced
# (aws_iam_role_policy_attachment.ecs_auto_scaling_group_iam_role_0 and _1), so a caller can add or
# remove a policy without this module changing (rules.md B-7). toset is safe because the ARNs are
# literal strings in configuration and are therefore known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "container_instance_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.container_instance_iam_role.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "container_instance_profile" {
  name_prefix = var.instance_profile_name_prefix
  # A single role name string, not the list CloudFormation's AWS::IAM::InstanceProfile Roles property
  # takes - an instance profile holds at most one role (rules.md A-3).
  role = aws_iam_role.container_instance_iam_role.name
}
locals {
  # /etc/ecs/ecs.config, which the ECS agent reads once at startup.
  #
  # ECS_CLUSTER is the only line the _monolithic template wrote, and it is the line that matters -
  # without it the agent joins the cluster literally named "default", creating it if necessary. That is
  # an unhelpful failure to diagnose, because everything succeeds: the instances are healthy, the agent
  # is running and registered, and the cluster this project created simply has no instances in it.
  #
  # The template wrote the cluster name as a literal. Here it arrives as a variable the caller takes
  # from the cluster module's output, so the name the agent is told and the name the service and the
  # deployment group use cannot diverge (rules.md B-5).
  ecs_config_lines = concat(
    ["ECS_CLUSTER=${var.cluster_name}"],
    [for key in sort(keys(var.ecs_config_options)) : "${key}=${var.ecs_config_options[key]}"],
  )

  container_instance_user_data = <<-EOT
    #!/bin/bash
    set -x

    mkdir -p /etc/ecs
    cat > /etc/ecs/ecs.config << 'TFECSCONFIG'
    ${join("\n", local.ecs_config_lines)}
    TFECSCONFIG
    EOT
}
resource "aws_launch_template" "container_instance_launch_template" {
  name_prefix = var.instance_name_prefix
  image_id    = var.ami_id
  key_name    = var.key_name
  # No instance_type here: the mixed instances policy below supplies the types as overrides, and a type
  # set in both places is a type the allocation strategy cannot choose between.
  user_data = base64encode(local.container_instance_user_data)
  iam_instance_profile {
    arn = aws_iam_instance_profile.container_instance_profile.arn
  }
  # security_groups belongs inside network_interfaces here rather than as vpc_security_group_ids on the
  # template; setting both is rejected by the provider. Deliberately no associate_public_ip_address:
  # these instances are in private subnets and reach the internet through their zone's NAT gateway.
  network_interfaces {
    device_index          = 0
    delete_on_termination = true
    security_groups       = [aws_security_group.container_instance_security_group.id]
  }
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = var.instance_name
    }
  }

  # The agent calls RegisterContainerInstance within seconds of boot, and without
  # AmazonEC2ContainerServiceforEC2Role already attached that call is denied and the instance never
  # joins. The instance profile reference orders this after the profile and the role but not after the
  # attachment, so the ordering has to be stated (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.container_instance_iam_role,
    aws_vpc_security_group_egress_rule.container_instance_egress,
  ]
}
resource "aws_autoscaling_group" "container_instance_asg" {
  name_prefix      = var.instance_name_prefix
  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity
  default_cooldown = var.default_cooldown
  # The group-side half of managed_termination_protection on the capacity provider below. ECS validates
  # the two as a pair: protection ENABLED requires this true, DISABLED requires it false.
  protect_from_scale_in = var.protect_from_scale_in
  vpc_zone_identifier   = var.subnet_ids
  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.container_instance_launch_template.id
        # latest_version rather than a pinned number, as the _monolithic template had it. A change to
        # the template - a new AMI id, a changed ecs.config - is picked up by instances launched after
        # the change and does nothing to the instances already running.
        version = aws_launch_template.container_instance_launch_template.latest_version
      }
      dynamic "override" {
        for_each = var.instance_types
        content {
          instance_type = override.value
        }
      }
    }
    instances_distribution {
      on_demand_base_capacity                  = var.on_demand_base_capacity
      on_demand_percentage_above_base_capacity = var.on_demand_percentage_above_base_capacity
      spot_allocation_strategy                 = var.spot_allocation_strategy
    }
  }

  lifecycle {
    # desired_capacity has two owners once managed scaling is enabled, and that is the whole point of
    # the setting: ECS reads the tasks waiting to be placed and sets the group's desired count from
    # them. The _monolithic template declared desired_capacity and nothing else, so the first apply set
    # it to 2, the capacity provider then moved it, and from that point every plan proposed moving it
    # back - and applying that plan would take capacity away from tasks ECS had just asked for it for.
    # A blue/green deployment makes this immediate rather than eventual: for the length of a deployment
    # both task sets are running, so ECS asks for roughly double the capacity.
    #
    # One field rather than the whole resource, for the reason rules.md E-8 gives: the AMI id, the
    # instance types and the subnets stay tracked, so a change to any of them is still a plan. The value
    # above is therefore the starting point only.
    ignore_changes = [desired_capacity]
  }

  # Not a reference to the ECS cluster, unlike the _monolithic template's depends_on. The cluster name
  # arrives as a variable and is interpolated into the launch template userdata, so the cluster is
  # already upstream through that value and the caller orders this module after the cluster module
  # (rules.md D-2). What no reference implies is the policy attachment, for the reason on the template.
  depends_on = [aws_iam_role_policy_attachment.container_instance_iam_role]
}
# The capacity provider, which is what lets an ECS service ask for capacity rather than only consume it.
#
# auto_scaling_group_arn is given the ARN. The _monolithic template passed the group's name into it:
#
#   auto_scaling_group_arn = aws_autoscaling_group.ecs_auto_scaling_group.name
#
# which is accepted - the ECS API documents the field as taking either - so apply succeeds and the
# provider works. The problem arrives afterwards. ECS stores the ARN, so the next refresh reads an ARN
# back into state where the configuration says a name, and the field cannot be updated in place, so
# every subsequent plan proposes replacing the capacity provider. That replacement then fails, because
# ECS refuses to delete a provider while the cluster's default strategy and a service's strategy still
# name it. The end state is a configuration that cannot be applied again without manual intervention,
# from a line that looked like it worked.
resource "aws_ecs_capacity_provider" "capacity_provider" {
  name = var.capacity_provider_name
  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.container_instance_asg.arn
    managed_draining               = var.managed_draining
    managed_termination_protection = var.managed_termination_protection
    managed_scaling {
      status                 = var.managed_scaling_status
      target_capacity        = var.managed_scaling_target_capacity
      instance_warmup_period = var.managed_scaling_instance_warmup_period
    }
  }
}
# Attaches the provider to the cluster and makes it the default, so a task run without a strategy of
# its own still lands on these instances.
#
# A separate resource rather than part of the cluster, which is what keeps the graph acyclic - see the
# ecs_cluster module. It is also what makes destroy work in the right order: it holds the only link
# from the cluster to the provider, so Terraform removes the link before deleting the provider, and ECS
# rejects deleting a provider that is still linked.
#
# .name rather than .id in both places. The _monolithic template wrote the resource's id, and this
# resource's id is its ARN - while PutClusterCapacityProviders documents capacityProviders and
# defaultCapacityProviderStrategy.capacityProvider as the provider's name. ECS reads the list back as
# names, so an ARN written here never matches what is returned and every plan proposes putting the same
# list again, forever. The ecs_service module makes the same correction in the service's strategy.
resource "aws_ecs_cluster_capacity_providers" "cluster_capacity_providers" {
  cluster_name       = var.cluster_name
  capacity_providers = [aws_ecs_capacity_provider.capacity_provider.name]
  default_capacity_provider_strategy {
    base              = var.default_strategy_base
    weight            = var.default_strategy_weight
    capacity_provider = aws_ecs_capacity_provider.capacity_provider.name
  }
}
