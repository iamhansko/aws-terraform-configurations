resource "aws_security_group" "container_instance_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2), and the egress rule is the
# fix for the hole that would otherwise have emptied the cluster.
#
# The _monolithic template's container instance group declared one inline ingress block and no egress. In
# CloudFormation that leaves the allow-all egress rule AWS adds at creation in place; Terraform removes it
# whenever a group is created, so the conversion left these instances with no way out.
#
# What that costs here is the entire cluster, in a way that produces no error message anywhere. The instances
# are in private subnets, so every outbound call goes through a NAT gateway: the ECS agent calling
# RegisterContainerInstance against ecs.<region>.amazonaws.com, the long poll it holds open for task
# assignments, the ECR authorization token and the image layers. With egress revoked none of that leaves the
# instance. The instances come up healthy in the Auto Scaling group and the cluster reports
# registeredContainerInstancesCount of zero - because an instance that never registers never becomes an ECS
# object that could report a problem. For this project that means the ECS MCP server would find a cluster
# with a capacity provider and no capacity, and every task placed on it would sit in PROVISIONING.
resource "aws_vpc_security_group_egress_rule" "container_instance_egress" {
  security_group_id = aws_security_group.container_instance_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# A map keyed by a caller-chosen label rather than a list, because the IDs come from another module and are
# unknown at plan time (rules.md B-8). each.key goes into the description so a plan shows where each rule came
# from.
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
# (aws_iam_role_policy_attachment.ecs_container_instance_iam_role_0 and _1), so a caller can add or remove a
# policy without this module changing (rules.md B-7). toset is safe because the ARNs are literal strings in
# configuration and are therefore known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "container_instance_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.container_instance_iam_role.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "container_instance_profile" {
  # A single role name string, not the list CloudFormation's AWS::IAM::InstanceProfile Roles property takes -
  # an instance profile holds at most one role (rules.md A-3).
  role = aws_iam_role.container_instance_iam_role.name
}
locals {
  # /etc/ecs/ecs.config, which the ECS agent reads once at startup.
  #
  # ECS_CLUSTER is the only line the _monolithic template wrote, and it is the line that matters: without it
  # the agent joins the cluster literally named "default", creating it if necessary. That failure is
  # particularly unhelpful to diagnose, because everything succeeds - the instances are healthy, the agent is
  # running and registered, and the cluster this project created simply has no instances in it.
  ecs_config_lines = concat(
    ["ECS_CLUSTER=${var.cluster_name}"],
    [for key in sort(keys(var.ecs_config_options)) : "${key}=${var.ecs_config_options[key]}"],
  )

  # Written with cat rather than appended with echo as the _monolithic template did. The result is the same
  # on a fresh instance; the difference is that the file then holds exactly what this module says, and the
  # extra options above cannot end up after a stale ECS_CLUSTER line.
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
  name_prefix   = "${var.instance_name}-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  user_data     = base64encode(local.container_instance_user_data)
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
    # internet through the NAT gateways.
  }
  # IMDSv2 only, as the _monolithic template had it. The ECS agent uses IMDSv2, and with the default hop limit
  # of one a container on the bridge network cannot reach the instance's credentials - a task gets its own
  # through its task role instead.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = var.instance_name
    }
  }

  # The agent calls RegisterContainerInstance within seconds of boot, and without
  # AmazonEC2ContainerServiceforEC2Role already attached that call is denied and the instance never joins. The
  # instance profile reference orders this after the profile and the role but not after the attachment, so the
  # ordering has to be stated (rules.md D-1). The egress rule is listed for the same reason: without it the
  # first instances boot into a group with no way out.
  depends_on = [
    aws_iam_role_policy_attachment.container_instance_iam_role,
    aws_vpc_security_group_egress_rule.container_instance_egress,
  ]
}
resource "aws_autoscaling_group" "container_instance_asg" {
  name_prefix      = "${var.instance_name}-"
  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity
  # Instances protected from scale-in or not. This is the group-side half of managed_termination_protection on
  # the capacity provider, and the two are validated as a pair.
  protect_from_scale_in = var.protect_from_scale_in
  vpc_zone_identifier   = var.subnet_ids

  launch_template {
    id = aws_launch_template.container_instance_launch_template.id
    # latest_version rather than a pinned number, as the _monolithic template had it. A change to the template
    # - a new AMI id, a changed ecs.config - is picked up by instances launched after the change, and does
    # nothing to the instances already running.
    version = aws_launch_template.container_instance_launch_template.latest_version
  }

  # As the _monolithic template had it. balanced-only keeps the instances spread evenly over the zones and
  # fails a launch rather than placing it in another zone when one zone has no capacity; balanced-best-effort is
  # the alternative that prefers getting the instance over the balance.
  availability_zone_distribution {
    capacity_distribution_strategy = var.capacity_distribution_strategy
  }

  # Wait for min_size healthy instances, but do not fail the apply on the first Failed scaling activity.
  #
  # With this false - the provider default, and what the _monolithic template had by omission - the provider
  # reads the group's activity log while it waits for capacity and turns any Failed activity into an apply
  # error, even though Auto Scaling itself retries the launch. On the first apply in an account the first
  # launch can fail with "Authentication Failure. Launching EC2 instance failed.": creating the first Auto
  # Scaling group creates AWSServiceRoleForAutoScaling, and the launch runs seconds later, before IAM has
  # propagated it. The next attempt succeeds; the apply has already failed by then, leaving a healthy group
  # tainted in state.
  #
  # With this true the wait still has to see min_size instances InService within wait_for_capacity_timeout (10
  # minutes by default), so a launch that can never succeed - a wrong AMI, a missing permission - still fails
  # the apply, as a timeout rather than with the activity's message. The message is then in the activity log,
  # which the scaling_activities_command output reads.
  ignore_failed_scaling_activities = true

  # ECS writes this tag onto the group when the capacity provider below is attached, with an empty value and
  # propagate_at_launch on. Declared here so it is Terraform's too: without it the next plan proposes removing
  # it, and an instance launched after that removal comes up untagged - which the provider documentation warns
  # skews managed scaling's metrics. The empty value is what ECS writes, so the first apply and ECS agree and no
  # later plan shows a change. The _monolithic template did not declare it.
  tag {
    key                 = "AmazonECSManaged"
    value               = ""
    propagate_at_launch = true
  }

  lifecycle {
    # desired_capacity has two owners once managed scaling is enabled, and this is the whole reason the setting
    # exists: ECS reads the tasks waiting to be placed and sets the group's desired count from them. The
    # _monolithic template declared desired_capacity and nothing else, so the first apply set it to 2, the
    # capacity provider then moved it - down to min_size on an empty cluster, up when Q deploys something - and
    # from that point every plan proposed moving it back. Applying that plan would take capacity away from
    # tasks ECS had just asked for it for.
    #
    # Ignoring the one field rather than the whole resource, for the reason rules.md E-8 gives for
    # ignore_fields over a blanket ignore_changes: the launch template version and the subnets stay tracked,
    # so a change to either is still a plan.
    ignore_changes = [desired_capacity]
  }

  # Not a reference to the ECS cluster, unlike the _monolithic template's depends_on. The cluster name arrives
  # as a variable and is interpolated into the launch template userdata, so the cluster is already upstream of
  # this group through that value - the caller orders the module after the cluster module (rules.md D-2).
  # What is not implied by any reference is the policy attachment, for the reason given on the launch
  # template.
  depends_on = [aws_iam_role_policy_attachment.container_instance_iam_role]
}
# The capacity provider, which is what lets ECS ask the group for capacity rather than just consume it.
#
# auto_scaling_group_arn is given the ARN, as the _monolithic template also did here. It is worth keeping:
# ECS also accepts the group's name in this field, stores the ARN either way, and a name in configuration is
# then read back as an ARN on the next refresh - a diff on a field that forces replacement, which ECS refuses
# while the cluster still names the provider.
resource "aws_ecs_capacity_provider" "capacity_provider" {
  name = var.capacity_provider_name
  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.container_instance_asg.arn
    managed_draining               = var.managed_draining
    managed_termination_protection = var.managed_termination_protection
    managed_scaling {
      status                    = var.managed_scaling_status
      target_capacity           = var.managed_scaling_target_capacity
      instance_warmup_period    = var.managed_scaling_instance_warmup_period
      minimum_scaling_step_size = var.managed_scaling_minimum_step_size
      maximum_scaling_step_size = var.managed_scaling_maximum_step_size
    }
  }
}
# Attaches the provider to the cluster, next to the Fargate providers, and makes it the default, so a task run
# without a strategy of its own lands on these instances.
#
# A separate resource rather than part of the cluster, and that is what keeps the dependency graph acyclic:
# the instances need the cluster name, the cluster needs the provider name, and the provider needs the group.
# It is also what makes destroy work in the right order - it holds the only link from the cluster to the
# provider, so Terraform removes the link before deleting the provider, and ECS rejects deleting a provider
# that is still linked.
#
# .name rather than .id in both places. The _monolithic template wrote
# aws_ecs_capacity_provider.ecs_ec2_capacity_provider.id, and that resource's id is its ARN - while
# PutClusterCapacityProviders documents capacityProviders and defaultCapacityProviderStrategy.capacityProvider
# as the provider's name. ECS reads the list back as names, so an ARN written here does not match what is
# returned and every plan proposes putting the same list again.
resource "aws_ecs_cluster_capacity_providers" "cluster_capacity_providers" {
  cluster_name       = var.cluster_name
  capacity_providers = concat([aws_ecs_capacity_provider.capacity_provider.name], var.additional_capacity_providers)
  default_capacity_provider_strategy {
    base              = var.default_strategy_base
    weight            = var.default_strategy_weight
    capacity_provider = aws_ecs_capacity_provider.capacity_provider.name
  }
}
