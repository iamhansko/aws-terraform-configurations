resource "aws_security_group" "container_instance_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  # Nothing adds rules to this group that Terraform does not track, so this only changes Terraform's
  # delete behaviour and costs nothing to leave on (rules.md F-2). It is here because the group is
  # referenced from the service group's rules, and revoking this group's own rules before deleting it
  # removes one way for a destroy to stall on a leftover reference.
  revoke_rules_on_delete = var.revoke_rules_on_delete
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2), and the egress rule is
# a fix rather than a transcription.
#
# The _monolithic template's group for these instances declared one ingress rule and no egress rule. In
# CloudFormation that leaves the allow-all egress AWS adds at creation in place; Terraform's inline
# ingress/egress are authoritative over the whole group, so declaring an ingress block revokes it.
#
# What that costs here is the entire cluster, with no error message anywhere. These instances sit in private
# subnets, so every outbound call goes through a NAT gateway: the ECS agent calling
# RegisterContainerInstance against ecs.<region>.amazonaws.com, the long poll it holds open for task
# assignments, the ECR authorization token and the image layers. With egress revoked none of it leaves the
# instance. The Auto Scaling group reports healthy instances, the cluster reports
# registeredContainerInstancesCount of zero - because an instance that never registers never becomes an ECS
# object that could report a problem - and the service says it "was unable to place a task because no
# container instance met all of its requirements", which points at placement constraints instead.
resource "aws_vpc_security_group_egress_rule" "container_instance_egress" {
  security_group_id = aws_security_group.container_instance_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# A map keyed by a caller-chosen label rather than a list, because the source IDs come from another module
# and are unknown at plan time (rules.md B-8). each.key goes into the description so a plan shows where
# each rule came from.
#
# The _monolithic template's single ingress rule here admitted all traffic from the VPC's default security
# group. Nothing in this project is launched into that group, so the rule admits nothing as built; it is
# reproduced because the original declared it, and the caller decides what goes in the map.
resource "aws_vpc_security_group_ingress_rule" "container_instance_source_group_ingress" {
  for_each                     = var.ingress_source_security_groups
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
  # A single role name string, not the list CloudFormation's AWS::IAM::InstanceProfile Roles property takes
  # (rules.md A-3).
  role = aws_iam_role.container_instance_iam_role.name
}
locals {
  # /etc/ecs/ecs.config, which the ECS agent reads once at startup.
  #
  # ECS_CLUSTER is the only line the _monolithic template wrote, and it is the line that matters: without it
  # the agent joins the cluster literally named "default", creating it if necessary. That failure is
  # unpleasant to diagnose, because nothing fails - the instances are healthy, the agent is running and
  # registered, and the cluster this project created simply has no instances in it.
  ecs_config_lines = concat(
    ["ECS_CLUSTER=${var.cluster_name}"],
    [for key in sort(keys(var.ecs_config_options)) : "${key}=${var.ecs_config_options[key]}"],
  )
  # No "dnf install -y aws-cfn-bootstrap", which the _monolithic template's launch template userdata ran.
  # It installs cfn-signal, and nothing here signals: there is no CloudFormation stack, and this launch
  # template never carried a CreationPolicy to report to in the first place - only the bastion did.
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
    name = aws_iam_instance_profile.container_instance_profile.name
  }
  vpc_security_group_ids = [aws_security_group.container_instance_security_group.id]
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  block_device_mappings {
    device_name = var.root_device_name
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = var.root_volume_type
      delete_on_termination = true
      encrypted             = true
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
  # The instance profile reference orders this after the profile and the role but not after the attachment
  # (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.container_instance_iam_role]
}
resource "aws_autoscaling_group" "container_instance_asg" {
  name_prefix         = "${var.instance_name}-"
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = var.subnet_ids
  # The group-side half of managed_termination_protection on the capacity provider below. ECS validates the
  # two as a pair: managed termination protection requires this to be true, and the _monolithic template
  # disabled the former, so this stays false.
  protect_from_scale_in = var.protect_from_scale_in
  launch_template {
    id = aws_launch_template.container_instance_launch_template.id
    # latest_version rather than a pinned number, as the _monolithic template had it. A change to the
    # template - a new AMI ID, a changed ecs.config - is then picked up by instances launched after the
    # change and does nothing to the ones already running.
    version = aws_launch_template.container_instance_launch_template.latest_version
  }
  availability_zone_distribution {
    capacity_distribution_strategy = var.capacity_distribution_strategy
  }
  # ECS writes this tag onto the group when the capacity provider below is created with managed scaling,
  # with an empty value and propagate_at_launch on. Declared here so it is Terraform's too: without it the
  # plan after the first apply proposes removing it, and an instance launched after that removal comes up
  # untagged - which the provider documentation warns skews managed scaling's metrics. The empty value is
  # what ECS writes, so ECS and this configuration agree and no later plan shows a change. Observed on this
  # project's first apply; the _monolithic template did not declare it.
  tag {
    key                 = "AmazonECSManaged"
    value               = ""
    propagate_at_launch = true
  }

  lifecycle {
    # desired_capacity has two owners once managed scaling is enabled, and this is the whole reason that
    # setting exists: ECS reads the tasks waiting to be placed and moves the group's desired count itself.
    # Without this, the first apply writes the value above, ECS then moves it, and from that point every
    # plan proposes moving it back - and applying that plan takes capacity away from tasks ECS had just
    # asked for it for. During a blue/green cutover that is capacity the replacement task set is sitting on.
    #
    # Ignoring the one field rather than the whole resource, which is the argument rules.md E-8 makes for
    # ignore_fields over a blanket freeze: the AMI ID, the instance type, the subnets and the size bounds
    # all stay tracked, so a change to any of them is still a plan.
    ignore_changes = [desired_capacity]
  }

  # Not a reference to the ECS cluster, unlike the _monolithic template's depends_on. The cluster name
  # arrives as a variable and is interpolated into the launch template userdata, so the cluster is already
  # upstream through that value and the caller orders this module after the cluster module (rules.md D-2).
  # What no reference implies is the policy attachment, for the reason given on the launch template.
  depends_on = [aws_iam_role_policy_attachment.container_instance_iam_role]
}
# The capacity provider, which is what lets ECS ask this group for capacity rather than only consume it.
#
# auto_scaling_group_arn is given the ARN, as the _monolithic template gave it. The ECS API accepts either
# the ARN or the group name, so a name applies cleanly - and then ECS stores the ARN, the next refresh reads
# an ARN back into state where the configuration says a name, the field cannot be updated in place, and
# every subsequent plan proposes replacing the capacity provider. That replacement fails, because ECS
# refuses to delete a provider the cluster's default strategy still names.
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
# own still lands on these instances - which is what the appspec the GitHub Actions workflow generates
# relies on when it names this provider for the replacement task set.
#
# A separate resource rather than part of the cluster module, and that is what keeps the graph acyclic: the
# instances need the cluster name, the cluster association needs the provider name, and the provider needs
# the group. It is also what makes destroy work in the right order, because it holds the only link from the
# cluster to the provider - Terraform removes the link before deleting the provider, and ECS rejects
# deleting a provider that is still linked.
#
# .name rather than .id, which is what the _monolithic template passed. This resource's id is its ARN,
# while PutClusterCapacityProviders documents capacityProviders and
# defaultCapacityProviderStrategy.capacityProvider as the provider's name. ECS reads the list back as
# names, so an ARN written here never matches what is returned and every plan proposes putting the same
# list again, forever.
resource "aws_ecs_cluster_capacity_providers" "cluster_capacity_providers" {
  cluster_name       = var.cluster_name
  capacity_providers = concat([aws_ecs_capacity_provider.capacity_provider.name], var.additional_capacity_providers)
  default_capacity_provider_strategy {
    base              = var.default_strategy_base
    weight            = var.default_strategy_weight
    capacity_provider = aws_ecs_capacity_provider.capacity_provider.name
  }
}
