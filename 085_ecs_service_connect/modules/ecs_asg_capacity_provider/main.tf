resource "aws_security_group" "container_instance_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2).
#
# The _monolithic template declared this group with one inline ingress block and no egress. In
# CloudFormation that leaves the allow-all egress rule AWS adds at creation in place; Terraform's inline
# blocks are authoritative over the whole group, so omitting egress revokes it.
#
# What that costs here is the entire cluster, and in a way that produces no error message anywhere. These
# instances are in private subnets, so every outbound call goes through the NAT gateway: the ECS agent
# calling RegisterContainerInstance against ecs.<region>.amazonaws.com, the long poll it holds open for
# task assignments, and - because the tasks run on EC2 rather than Fargate - every image pull and every
# awslogs write, which the Docker daemon makes from the instance's own interface, not from the task ENI.
# With egress revoked none of that leaves the instance. The instances come up healthy in the Auto Scaling
# group, and the cluster reports registeredContainerInstancesCount of zero - because an instance that never
# registers never becomes an ECS object that could report a problem. The service then says it "was unable
# to place a task because no container instance met all of its requirements", which points at placement
# constraints rather than at networking.
resource "aws_vpc_security_group_egress_rule" "container_instance_egress" {
  security_group_id = aws_security_group.container_instance_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# Nothing reaches these instances inbound, which is why the default here is no ingress rule at all.
#
# The _monolithic template admitted all traffic from the VPC default security group, which nothing in the
# project is a member of, so the rule matched no packet. It also would not have mattered if something had
# been: the tasks use awsvpc networking, so each has its own ENI in the task security group, and the
# traffic between tasks - including Service Connect and Cloud Map lookups in the sibling projects - goes
# ENI to ENI without touching this group. The instance's own interface carries only its outbound calls.
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
# (aws_iam_role_policy_attachment.ecs_container_instance_iam_role_0 and _1), so a caller can add or remove
# a policy without this module changing (rules.md B-7). toset is safe because the ARNs are literal strings
# in configuration and are therefore known at plan time (rules.md B-8).
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
  #
  # Written with cat > rather than the template's echo >>, so a second run of cloud-init on the same
  # instance cannot append a second ECS_CLUSTER line, and with set -x rather than -xe: there is no step
  # after this one that a failure here should prevent.
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
  # IMDSv2 only, as the _monolithic template had it. The hop limit stays at its default of 1, which is
  # what the ECS agent on the host needs and what keeps a container on a bridge network from reaching the
  # instance's credentials - awsvpc tasks are blocked from the endpoint by the agent regardless.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  # No block device mapping unless root_volume_size is set, which is what the _monolithic template had:
  # the ECS-optimized AMI's own 30 GiB root volume.
  dynamic "block_device_mappings" {
    for_each = var.root_volume_size == null ? [] : [var.root_volume_size]
    content {
      device_name = var.root_device_name
      ebs {
        volume_size           = block_device_mappings.value
        volume_type           = var.root_volume_type
        delete_on_termination = true
      }
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
  # attachment, so the ordering has to be stated (rules.md D-1). The egress rule is listed for the same
  # reason: the first thing the agent does is call out.
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
  default_cooldown = var.default_cooldown
  # Instances protected from scale-in or not. This is the group-side half of
  # managed_termination_protection on the capacity provider, and the two are validated as a pair.
  protect_from_scale_in = var.protect_from_scale_in
  vpc_zone_identifier   = var.subnet_ids

  # Wait for min_size healthy instances, but do not fail the apply on the first Failed scaling activity.
  #
  # With this false - the provider default, and what the _monolithic template had by omission - the
  # provider reads the group's activity log while it waits for capacity and turns any Failed activity into
  # an apply error, even though Auto Scaling itself retries the launch. On the first apply in an account
  # that happens reliably: creating the first Auto Scaling group creates AWSServiceRoleForAutoScaling, and
  # the group's first launch runs a few seconds later, before IAM has propagated that role, and fails with
  # "Authentication Failure. Launching EC2 instance failed." The next attempt succeeds, but the provider's
  # apply has already failed by then, leaving a healthy group tainted in state.
  #
  # With this true the wait still has to see min_size instances InService within wait_for_capacity_timeout
  # (10 minutes by default); a launch that can never succeed - a wrong AMI, a missing permission - still
  # fails the apply, as a timeout rather than with the activity's message. The message is then in the
  # activity log, which the scaling_activities_command output reads.
  ignore_failed_scaling_activities = true

  launch_template {
    id = aws_launch_template.container_instance_launch_template.id
    # latest_version rather than a pinned number, as the _monolithic template had it. A change to the
    # template - a new AMI id, a changed ecs.config - is picked up by instances launched after the change,
    # and does nothing to the instances already running.
    version = aws_launch_template.container_instance_launch_template.latest_version
  }

  # As the _monolithic template had it. balanced-only makes Auto Scaling refuse to launch into another zone
  # when the one it is balancing towards has no capacity, rather than over-filling the zone that does; for a
  # demo cluster of two instances that is the setting that keeps one instance in each zone.
  availability_zone_distribution {
    capacity_distribution_strategy = var.capacity_distribution_strategy
  }

  # ECS writes this tag onto the group when the capacity provider below is attached, with an empty value
  # and propagate_at_launch on. Declared here so it is Terraform's too: without it the next plan proposes
  # removing it, and an instance launched after that removal comes up untagged - which the provider
  # documentation warns skews managed scaling's metrics. The empty value is what ECS writes, so the first
  # apply and ECS agree and no later plan shows a change. The _monolithic template did not declare it.
  tag {
    key                 = "AmazonECSManaged"
    value               = ""
    propagate_at_launch = true
  }

  lifecycle {
    # desired_capacity has two owners once managed scaling is enabled, and this is the whole reason the
    # setting exists: ECS reads the tasks waiting to be placed and sets the group's desired count from
    # them. The _monolithic template declared desired_capacity and nothing else, so the first apply set it
    # to 2, the capacity provider then moved it, and from that point every plan proposed moving it back -
    # and applying that plan would take capacity away from tasks ECS had just asked for it for.
    #
    # Ignoring the one field rather than the whole resource, for the reason rules.md E-8 gives for
    # ignore_fields over a blanket ignore_changes: the AMI id, the instance type and the subnets stay
    # tracked, so a change to any of them is still a plan.
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
# auto_scaling_group_arn is given the ARN, as the _monolithic template did. ECS also accepts the group's
# name in this field and stores the ARN either way; a name here would read back as an ARN on the next
# refresh, and the field forces replacement, which ECS refuses while the cluster and a service still name
# the provider.
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
# Attaches the provider to the cluster and makes it the default, so a task run without a strategy of its
# own still lands on these instances.
#
# A separate resource rather than part of the cluster, and that is what keeps the dependency graph
# acyclic: the instances need the cluster name, the cluster needs the provider name, and the provider
# needs the group. This resource is also what makes destroy work in the right order - it holds the only
# link from the cluster to the provider, so Terraform removes the link before deleting the provider, and
# ECS rejects deleting a provider that is still linked. It is also what a service naming this provider has
# to wait for: CreateService rejects a strategy naming a provider not yet associated with the cluster, and
# the _monolithic template's services referenced the provider resource only, which does not order them
# after this association.
#
# .name rather than .id in both places. The _monolithic template wrote
# aws_ecs_capacity_provider.ecs_ec2_capacity_provider.id, and this resource's id is its ARN - while
# PutClusterCapacityProviders documents capacityProviders and
# defaultCapacityProviderStrategy.capacityProvider as the provider's name. ECS reads the list back as
# names, so an ARN written here does not match what is returned and every plan proposes putting the same
# list again, forever. The same substitution appears in the service's strategy, and the ecs_service module
# makes the same correction.
resource "aws_ecs_cluster_capacity_providers" "cluster_capacity_providers" {
  cluster_name       = var.cluster_name
  capacity_providers = concat([aws_ecs_capacity_provider.capacity_provider.name], var.additional_cluster_capacity_providers)
  default_capacity_provider_strategy {
    base              = var.default_strategy_base
    weight            = var.default_strategy_weight
    capacity_provider = aws_ecs_capacity_provider.capacity_provider.name
  }
}
