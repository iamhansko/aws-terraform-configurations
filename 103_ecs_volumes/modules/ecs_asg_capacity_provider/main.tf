resource "aws_security_group" "container_instance_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2), and the egress rule
# is the same fix the image builder module describes - this group had the same hole.
#
# The _monolithic template's container instance group declared no rules at all. In CloudFormation that
# leaves the allow-all egress rule AWS adds at creation in place; Terraform's inline blocks are
# authoritative over the whole group, so omitting them revokes it.
#
# What that costs here is the entire cluster, and in a way that produces no error message anywhere. These
# instances are in private subnets, so every outbound call goes through the NAT gateway: the ECS agent
# calling RegisterContainerInstance against ecs.<region>.amazonaws.com, the long poll it holds open for
# task assignments, the ECR authorization token and the image layers. With egress revoked none of that
# leaves the instance. The instances come up healthy in the Auto Scaling group, and the cluster reports
# registeredContainerInstancesCount of zero - because an instance that never registers never becomes an
# ECS object that could report a problem. The service then says it "was unable to place a task because no
# container instance met all of its requirements", which points at placement constraints rather than at
# networking.
resource "aws_vpc_security_group_egress_rule" "container_instance_egress" {
  security_group_id = aws_security_group.container_instance_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# Nothing reaches these instances inbound as the project is built: the tasks use host networking but
# publish no ports, and there is no load balancer. This stays for a caller that adds one.
#
# A map keyed by a caller-chosen label rather than a list, because the IDs come from another module and
# are unknown at plan time (rules.md B-8). each.key goes into the description so a plan shows where each
# rule came from.
resource "aws_vpc_security_group_ingress_rule" "container_instance_source_group_ingress" {
  for_each = var.ingress_source_security_groups

  security_group_id            = aws_security_group.container_instance_security_group.id
  description                  = "All traffic from the ${each.key} security group"
  ip_protocol                  = "-1"
  referenced_security_group_id = each.value
}
resource "aws_iam_role" "container_instance_iam_role" {
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
# (aws_iam_role_policy_attachment.ecs_asg_iam_role_0 and _1), so a caller can add or remove a policy
# without this module changing (rules.md B-7). toset is safe because the ARNs are literal strings in
# configuration and are therefore known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "container_instance_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.container_instance_iam_role.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "container_instance_profile" {
  # A single role name string, not the list CloudFormation's AWS::IAM::InstanceProfile Roles property
  # takes - an instance profile holds at most one role (rules.md A-3).
  role = aws_iam_role.container_instance_iam_role.name
}
locals {
  # /etc/ecs/ecs.config, which the ECS agent reads once at startup.
  #
  # ECS_CLUSTER is the only line the _monolithic template wrote, and it is the line that matters: without
  # it the agent joins the cluster literally named "default", creating it if necessary. That failure is
  # particularly unhelpful to diagnose, because everything succeeds - the instances are healthy, the
  # agent is running and registered, and the cluster this project created simply has no instances in it.
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

    # The bind mount source. Docker creates a missing bind-mount source directory itself, so this line is
    # not what makes the mount work - it is what makes a wrong path visible. Without it, a task pointed at
    # a path nobody created still starts, and the directory being inspected on the host stays empty while
    # the writes pile up somewhere else on the same volume.
    mkdir -p ${var.host_volume_path}
    EOT
}
resource "aws_launch_template" "container_instance_launch_template" {
  name_prefix = "${var.instance_name}-"
  image_id    = var.ami_id
  key_name    = var.key_name
  # No instance_type here: the mixed instances policy below supplies the types as overrides, and a type
  # set in both places is a type the allocation strategy cannot choose between.
  user_data = base64encode(local.container_instance_user_data)
  iam_instance_profile {
    arn = aws_iam_instance_profile.container_instance_profile.arn
  }
  # security_groups belongs inside network_interfaces here rather than as vpc_security_group_ids on the
  # template; setting both is rejected by the provider.
  network_interfaces {
    device_index          = 0
    delete_on_termination = true
    security_groups       = [aws_security_group.container_instance_security_group.id]
    # Deliberately not associate_public_ip_address: these instances are in private subnets and reach the
    # internet through the NAT gateway, which is what the regional gateway in the network module exists
    # for.
  }
  # The _monolithic template declared no block device mapping at all, taking the ECS-optimized AMI's own
  # 30 GiB gp2 root volume. Both halves of that are changed here, and the volume type is the more
  # important one: gp2 throughput is a function of volume size, so a demo that measures write throughput
  # with direct I/O onto a gp2 root volume is largely measuring how big that volume is. gp3 decouples
  # them, which is what makes the dd figures in the container's log mean something.
  block_device_mappings {
    device_name = var.root_device_name
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = var.root_volume_type
      delete_on_termination = true
    }
  }
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = var.instance_name
    }
  }

  # The agent calls RegisterContainerInstance within seconds of boot, and without
  # AmazonEC2ContainerServiceforEC2Role already attached that call is denied and the instance never joins.
  # The instance profile reference orders this after the profile and the role but not after the
  # attachment, so the ordering has to be stated (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.container_instance_iam_role]
}
resource "aws_autoscaling_group" "container_instance_asg" {
  name_prefix      = "${var.instance_name}-"
  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity
  default_cooldown = var.default_cooldown
  # Instances protected from scale-in or not. This is the group-side half of
  # managed_termination_protection on the capacity provider, and the two are validated as a pair.
  protect_from_scale_in = var.protect_from_scale_in
  vpc_zone_identifier   = var.subnet_ids

  # Wait for min_size healthy instances, but do not fail the apply on the first Failed scaling activity.
  #
  # With this false - the provider default, and what the _monolithic template had by omission - the
  # provider reads the group's activity log while it waits for capacity and turns any Failed activity into
  # an apply error, even though Auto Scaling itself retries the launch. This group produces two kinds of
  # Failed activity that are retried and recover, and either one is enough to fail the apply:
  #
  #   - "Authentication Failure. Launching EC2 instance failed." on the first apply in an account. Creating
  #     the first Auto Scaling group creates AWSServiceRoleForAutoScaling, and the group's first launch
  #     runs about three seconds later, before IAM has propagated that role. The next attempt, a minute on,
  #     succeeds - and also creates AWSServiceRoleForEC2Spot, because this group requests spot. Only the
  #     provider's apply has already failed by then, leaving a healthy group tainted in state.
  #   - "Could not launch Spot Instances. UnfulfillableCapacity" whenever one zone has no spot capacity for
  #     the requested types. Auto Scaling then launches in the other zone and keeps retrying the empty one
  #     to rebalance, so the group reaches its capacity while the log fills with Failed entries.
  #
  # The provider skips only "Invalid IAM Instance Profile" as retryable, so neither is covered. With this
  # true the wait still has to see min_size instances InService within wait_for_capacity_timeout (10
  # minutes by default); a launch that can never succeed - a wrong AMI, a missing permission - still fails
  # the apply, as a timeout rather than with the activity's message. The message is then in the activity
  # log, which the scaling_activities_command output reads.
  ignore_failed_scaling_activities = true

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.container_instance_launch_template.id
        # latest_version rather than a pinned number, as the _monolithic template had it. It means a
        # change to the template - a new AMI id, a changed ecs.config - is picked up by instances launched
        # after the change, and does nothing to the instances already running.
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

  # ECS writes this tag onto the group when the capacity provider below is attached, with an empty value
  # and propagate_at_launch on. Declared here so it is Terraform's too: without it the next plan proposes
  # removing it, and an instance launched after that removal comes up untagged - which the provider
  # documentation warns skews managed scaling's metrics. The empty value is what ECS writes, so the first
  # apply and ECS agree and no later plan shows a change.
  tag {
    key                 = "AmazonECSManaged"
    value               = ""
    propagate_at_launch = true
  }

  lifecycle {
    # desired_capacity has two owners once managed scaling is enabled, and this is the whole reason the
    # setting exists: ECS reads the tasks waiting to be placed and sets the group's desired count from
    # them. The _monolithic template declared desired_capacity and nothing else, so the first apply set it
    # to 4, the capacity provider then moved it, and from that point every plan proposed moving it back -
    # and applying that plan would take capacity away from tasks ECS had just asked for it for.
    #
    # Ignoring the one field rather than the whole resource, for the reason rules.md E-8 gives for
    # ignore_fields over a blanket ignore_changes: the AMI id, the instance types and the subnets stay
    # tracked, so a change to any of them is still a plan.
    #
    # The value written above is therefore the starting point only, which is the right way to read it -
    # four instances at launch, and whatever ECS decides afterwards.
    ignore_changes = [desired_capacity]
  }

  # Not a reference to the ECS cluster, unlike the _monolithic template's depends_on. The cluster name
  # arrives as a variable and is interpolated into the launch template userdata, so the cluster is already
  # upstream of this group through that value - the caller orders the module after the cluster module
  # (rules.md D-2). What is not implied by any reference is the policy attachment, for the reason given on
  # the launch template.
  depends_on = [aws_iam_role_policy_attachment.container_instance_iam_role]
}
# The capacity provider, which is what lets an ECS service ask for capacity rather than just consume it.
#
# auto_scaling_group_arn is given the ARN. The _monolithic template passed the Auto Scaling group's name
# into it:
#
#   auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.name
#
# which is accepted - the ECS API documents the field as taking the ARN or the group name - so apply
# succeeds and the capacity provider works. The problem arrives afterwards. ECS stores the ARN, so the
# next refresh reads an ARN back into state where the configuration says a name, and the field cannot be
# updated in place, so every subsequent plan proposes replacing the capacity provider. That replacement
# then fails, because ECS refuses to delete a capacity provider while the cluster's default strategy and
# a service's strategy still name it. The end state is a configuration that cannot be applied again
# without manual intervention, from a line that looked like it worked.
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
      # minimum_scaling_step_size and maximum_scaling_step_size are deliberately left out, as the
      # _monolithic template left them out. Both are optional and computed, so ECS picks its own defaults
      # and the provider records what ECS chose; writing a value here instead would be choosing a scaling
      # step without a reason to.
    }
  }
}
# Attaches the provider to the cluster and makes it the default, so a task run without a strategy of its
# own still lands on these instances.
#
# A separate resource rather than part of the cluster, and that is what keeps the dependency graph
# acyclic: the instances need the cluster name, the cluster needs the provider name, and the provider
# needs the group. This resource is also what makes destroy work in the right order - it holds the only
# link from the cluster to the provider, so Terraform removes the link before deleting the provider, and
# ECS rejects deleting a provider that is still linked.
#
# .name rather than .id in both places. The _monolithic template wrote
# aws_ecs_capacity_provider.ecs_capacity_provider.id, and this resource's id is its ARN - while
# PutClusterCapacityProviders documents capacityProviders and
# defaultCapacityProviderStrategy.capacityProvider as the provider's name, with no mention of an ARN
# being accepted (its cluster argument, on the same page, documents both - so the omission is the point).
# ECS reads the list back as names, so an ARN written here does not match what is returned and every plan
# proposes putting the same list again, forever. The same substitution appears in the service's strategy,
# and the ecs_service module makes the same correction.
resource "aws_ecs_cluster_capacity_providers" "cluster_capacity_providers" {
  cluster_name       = var.cluster_name
  capacity_providers = [aws_ecs_capacity_provider.capacity_provider.name]
  default_capacity_provider_strategy {
    base              = var.default_strategy_base
    weight            = var.default_strategy_weight
    capacity_provider = aws_ecs_capacity_provider.capacity_provider.name
  }
}
