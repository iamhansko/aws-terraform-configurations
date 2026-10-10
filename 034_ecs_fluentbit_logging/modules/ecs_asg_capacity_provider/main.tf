resource "aws_security_group" "container_instance_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2), and the egress rule
# is a fix rather than a transcription.
#
# The _monolithic template's container instance group declared one ingress rule and no egress rule. In
# CloudFormation that leaves the allow-all egress rule AWS adds at creation in place; Terraform's inline
# blocks are authoritative over the whole group, so declaring any rule and omitting egress revokes it.
#
# This is the most expensive instance of that mistake in this project, and it fails in two layers.
#
# First the instances never join. These are on public subnets with public addresses, so every outbound
# call leaves through the internet gateway: the ECS agent's RegisterContainerInstance against
# ecs.<region>.amazonaws.com, the long poll it holds open for task assignments, and the ECR token and
# image layers for both containers. With egress revoked none of that leaves. The Auto Scaling group
# reports healthy instances, the cluster reports registeredContainerInstancesCount of zero - an instance
# that never registers never becomes an ECS object that could report a problem - and the service then
# says it "was unable to place a task because no container instance met all of its requirements", which
# points at placement constraints rather than at networking.
#
# Second, and specific to this project: even with tasks placed, this is the group Fluent Bit ships
# through. The tasks use bridge networking, so they share this instance's network interface and this
# group, and every PutLogEvents call to logs.<region>.amazonaws.com is outbound from here. A narrower
# break - egress to ECR but not to CloudWatch Logs, say - produces a running, healthy task, an
# application printing happily to stdout, and an empty log group. Nothing in ECS reports it; the only
# place it appears is the log router's own log.
resource "aws_vpc_security_group_egress_rule" "container_instance_egress" {
  security_group_id = aws_security_group.container_instance_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# Inbound, which nothing in this project needs: the tasks publish no ports and there is no load balancer.
#
# The _monolithic template's one ingress rule allowed all traffic from the VPC's default security group -
# a group that nothing in that template was ever placed in, so the rule admitted nothing. What it was
# reaching for was "from inside the VPC", and the root supplies the workbench's group here instead, which
# is a group something is actually in.
#
# A map keyed by a caller-chosen label rather than a list, because these IDs come from another module and
# are therefore unknown at plan time - a for_each key has to be known then (rules.md B-8). each.key goes
# into the description so a plan shows where each rule came from.
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
# a policy without this module changing (rules.md B-7). toset is safe because these ARNs are literal
# strings in configuration and are known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "container_instance_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.container_instance_iam_role.name
  policy_arn = each.value
}
# name_prefix rather than the "ContainerInstanceProfile-<uuid slice>" the _monolithic template built from
# its stand-in for AWS::StackId. Same property - two copies of this project in one account do not collide
# with EntityAlreadyExists - without the random provider.
#
# role takes a single role name string, not the list CloudFormation's AWS::IAM::InstanceProfile Roles
# property accepts (rules.md A-3).
resource "aws_iam_instance_profile" "container_instance_profile" {
  name_prefix = var.instance_profile_name_prefix
  role        = aws_iam_role.container_instance_iam_role.name
}
locals {
  # /etc/ecs/ecs.config, which the ECS agent reads once at startup.
  #
  # ECS_CLUSTER is the only line the _monolithic template wrote, and it is the line that matters: without
  # it the agent joins the cluster literally named "default", creating it if necessary. That failure is
  # unhelpful to diagnose because nothing fails - the instances are healthy, the agent is running and
  # registered, and the cluster this project created simply has no instances in it.
  ecs_config_lines = concat(
    ["ECS_CLUSTER=${var.cluster_name}"],
    [for key in sort(keys(var.ecs_config_options)) : "${key}=${var.ecs_config_options[key]}"],
  )

  # Appended rather than written. The distinction matters more here than it looks, because this project
  # depends on two agent settings that come from the AMI's side of this file rather than from Terraform:
  #
  #   - awslogs has to be among the agent's available logging drivers, or the log router container's own
  #     log configuration makes the task unplaceable. The agent's own default is ["json-file","none"]; it
  #     is the ECS-optimized AMI's ecs-init package that adds awslogs, which is why the AWS documentation
  #     tells you to set ECS_AVAILABLE_LOGGING_DRIVERS yourself only when using a custom AMI.
  #   - ECS_ENABLE_AWSLOGS_EXECUTIONROLE_OVERRIDE has to be true for that driver to authenticate as the
  #     task execution role rather than as this instance role. ecs-init sets it true from v1.16.0-1.
  #
  # Overwriting this file with "cat >" would be the tidier-looking choice and would discard anything the
  # AMI put in it. Appending keeps those defaults and still lets ecs_config_options override them, because
  # the agent takes the last assignment of a key.
  #
  # The application container's awsfirelens driver is not subject to the same requirement: the agent
  # registers the firelens capabilities unconditionally rather than from the available-drivers list, so
  # fluentd does not have to appear here.
  container_instance_user_data = <<-EOT
    #!/bin/bash
    set -x

    mkdir -p /etc/ecs
    cat >> /etc/ecs/ecs.config << 'TFECSCONFIG'
    ${join("\n", local.ecs_config_lines)}
    TFECSCONFIG
    EOT
}
# No cfn-bootstrap install, which the _monolithic template's version of this script ended with:
#
#   dnf install -y aws-cfn-bootstrap
#
# It was there so that a cfn-signal call could follow, and there is no CloudFormation stack here to signal.
# Nothing in this project calls it, so the line only slowed every instance launch down by one package
# install (rules.md D-5 - the ordering this project needs comes from marker files in the root instead).
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
  #
  # associate_public_ip_address is load-bearing rather than incidental. This VPC has no private subnets
  # and no NAT gateway (see the network module), so an instance without a public address has no outbound
  # path at all - it cannot register with ECS, cannot pull either image, and cannot deliver a log record.
  network_interfaces {
    device_index                = 0
    delete_on_termination       = true
    associate_public_ip_address = true
    security_groups             = [aws_security_group.container_instance_security_group.id]
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  # No block_device_mappings, as the _monolithic template had it, so the instance keeps the ECS-optimized
  # AMI's own root volume. Declaring one means naming the AMI's root device correctly, and a wrong name
  # does not fail - it attaches a second, unformatted volume and leaves the root at the AMI's size. The
  # two images this project pulls are small enough that there is nothing to gain by taking that on.
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
  # Both public subnets, as the _monolithic template had it, so a zone short of capacity is survivable.
  vpc_zone_identifier = var.subnet_ids
  # Instances protected from scale-in or not. This is the group-side half of
  # managed_termination_protection on the capacity provider, and the two are validated as a pair.
  protect_from_scale_in = var.protect_from_scale_in
  launch_template {
    id = aws_launch_template.container_instance_launch_template.id
    # latest_version rather than a pinned number, as the _monolithic template had it. A change to the
    # template - a new AMI id, a changed ecs.config - is then picked up by instances launched after the
    # change, and does nothing to the instances already running.
    version = aws_launch_template.container_instance_launch_template.latest_version
  }

  lifecycle {
    # desired_capacity has two owners once managed scaling is enabled, which is the whole reason that
    # setting exists: ECS reads the tasks waiting to be placed and sets the group's desired count from
    # them. The _monolithic template declared desired_capacity with managed scaling left at the API's
    # default, so the first apply set the count, the capacity provider could then move it, and from that
    # point every plan would propose moving it back - and applying that plan would take capacity away
    # from tasks ECS had just asked for it for.
    #
    # Ignoring the one field rather than the whole resource, for the reason rules.md E-8 gives: the AMI
    # id, the instance type and the subnets stay tracked, so a change to any of them is still a plan. The
    # value above is therefore the starting point only.
    ignore_changes = [desired_capacity]
  }

  # Not a reference to the ECS cluster, unlike the _monolithic template's depends_on. The cluster name
  # arrives as a variable and is interpolated into the launch template userdata, so the cluster is already
  # upstream of this group through that value, and the caller orders the module after the cluster module
  # (rules.md D-2). What no reference implies is the policy attachment, for the reason on the template.
  depends_on = [aws_iam_role_policy_attachment.container_instance_iam_role]
}
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
# Attaches the provider to the cluster and makes it the default, so a task run without a strategy of its
# own still lands on these instances.
#
# .name rather than .id in both places. The _monolithic template wrote
# aws_ecs_capacity_provider.ecs_ec2_capacity_provider.id, and this resource's id is its ARN - while
# PutClusterCapacityProviders documents capacityProviders and
# defaultCapacityProviderStrategy.capacityProvider as the provider's name, with no mention of an ARN being
# accepted. Its cluster argument, on the same page, documents both, so the omission is the point. ECS
# reads the list back as names, so an ARN written here does not match what is returned and every plan
# proposes putting the same list again, forever. The same substitution was in the service's strategy, and
# the ecs_firelens_service module makes the same correction.
#
# A separate resource rather than part of the cluster is also what makes destroy work in the right order:
# it holds the only link from the cluster to the provider, so Terraform removes the link before deleting
# the provider, and ECS rejects deleting a provider that is still linked.
resource "aws_ecs_cluster_capacity_providers" "cluster_capacity_providers" {
  cluster_name       = var.cluster_name
  capacity_providers = [aws_ecs_capacity_provider.capacity_provider.name]
  default_capacity_provider_strategy {
    base              = var.default_strategy_base
    weight            = var.default_strategy_weight
    capacity_provider = aws_ecs_capacity_provider.capacity_provider.name
  }
}
