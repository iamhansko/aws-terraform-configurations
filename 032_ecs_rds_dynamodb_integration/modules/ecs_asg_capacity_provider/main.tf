resource "aws_security_group" "container_instance_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2), and the egress rule is
# the fix the other three security groups in this project needed too.
#
# The _monolithic template gave this group one inline ingress block - all traffic from the VPC's default
# security group, which nothing joins - and no egress block. CloudFormation leaves the allow-all egress rule
# AWS adds at creation in place when a template names only ingress; Terraform's inline blocks are
# authoritative over the whole group and revoke it.
#
# What that costs here is the entire cluster, with no error message anywhere. These instances are in private
# subnets, so every outbound call goes through a NAT gateway: the ECS agent calling
# RegisterContainerInstance against ecs.<region>.amazonaws.com, the long poll it holds open for task
# assignments, the ECR authorization token and the image layers. With egress revoked none of it leaves the
# instance. The instances come up healthy in the Auto Scaling group and the cluster reports
# registeredContainerInstancesCount of zero - because an instance that never registers never becomes an ECS
# object that could report a problem. The services then say they were "unable to place a task because no
# container instance met all of its requirements", which points at placement constraints rather than at
# networking.
resource "aws_vpc_security_group_egress_rule" "container_instance_egress" {
  security_group_id = aws_security_group.container_instance_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# Nothing reaches these instances inbound as the project is built, and that is a consequence of awsvpc
# networking rather than an omission: each task gets its own ENI in the task security group, so traffic to a
# container never touches this group. It stays as an extension point for a caller that adds bridge or host
# networking, or a load balancer targeting instances.
#
# A map keyed by a caller-chosen label rather than a list, because the IDs come from other modules and are
# unknown at plan time (rules.md B-8). each.key goes into the description so a plan shows the source.
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
# (ecs_container_instance_iam_role_0 and _1), so a caller can add or remove a policy without this module
# changing (rules.md B-7). toset is safe because the ARNs are configuration literals, known at plan time
# (rules.md B-8).
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
  # ECS_CLUSTER is the only line the _monolithic template wrote and it is the line that matters: without it
  # the agent joins the cluster literally named "default", creating it if necessary. That failure is
  # unusually unhelpful to diagnose, because nothing fails - the instances are healthy, the agent is running
  # and registered, and the cluster this project created simply has no instances in it.
  #
  # ECS_ENABLE_TASK_ENI is deliberately absent. Every task definition here uses awsvpc, which needs the
  # instance to advertise the ecs.capability.task-eni attribute, and it is tempting to set the variable for
  # it - but the ECS-optimized AMI registers that capability automatically from ecs-init 1.15.0-4 onward, so
  # the line would be noise. What does constrain this cluster is ENI count rather than configuration: an
  # awsvpc task consumes one ENI on its instance and the primary interface uses one, so a t3.medium runs two
  # such tasks at most. Three instances and three services is comfortable; nine services on three instances
  # would not place, and the symptom is a RESOURCE:ENI placement failure in the service's events.
  ecs_config_lines = concat(
    ["ECS_CLUSTER=${var.cluster_name}"],
    [for key in sort(keys(var.ecs_config_options)) : "${key}=${var.ecs_config_options[key]}"],
  )
  # The template's userdata was this echo plus "dnf install -y aws-cfn-bootstrap". The install is dropped:
  # nothing on these instances calls cfn-init or cfn-signal, the package is not in the Amazon Linux 2023
  # repositories, and the line therefore spent its time failing.
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
  # vpc_security_group_ids rather than a network_interfaces block, as the template had it. Setting both is
  # rejected by the provider, and there is nothing here that needs the block: these instances are in private
  # subnets and take no public address.
  vpc_security_group_ids = [aws_security_group.container_instance_security_group.id]
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = var.metadata_http_tokens
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
  launch_template {
    id = aws_launch_template.container_instance_launch_template.id
    # latest_version rather than a pinned number, as the template had it. A change to the template - a new
    # AMI id, a changed ecs.config - is picked up by instances launched after the change, and does nothing
    # to the instances already running.
    version = aws_launch_template.container_instance_launch_template.latest_version
  }
  availability_zone_distribution {
    capacity_distribution_strategy = var.capacity_distribution_strategy
  }
  lifecycle {
    # desired_capacity has two owners once managed scaling is enabled, and that is the whole reason the
    # setting exists: ECS reads the tasks waiting to be placed and sets the group's desired count from them.
    # The template declared desired_capacity and nothing else, so the first apply set it, the capacity
    # provider then moved it, and from that point every plan proposed moving it back - and applying that
    # plan would take capacity away from tasks ECS had just asked for it for.
    #
    # Ignoring the one field rather than the whole resource, for the reason rules.md E-8 gives: the AMI id,
    # the instance type and the subnets stay tracked, so a change to any of them is still a plan. The value
    # above is the starting point only, which is the right way to read it.
    ignore_changes = [desired_capacity]
  }
  # Not a reference to the ECS cluster, unlike the template's depends_on. The cluster name arrives as a
  # variable and is interpolated into the launch template userdata, so the cluster is already upstream
  # through that value, and the caller orders this module after the cluster module (rules.md D-2). What no
  # reference implies is the policy attachment, for the reason given on the launch template.
  depends_on = [aws_iam_role_policy_attachment.container_instance_iam_role]
}
# The capacity provider, which is what lets an ECS service ask for capacity rather than merely consume it.
#
# auto_scaling_group_arn is given the ARN. The template passed the group's name:
#
#   auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.name
#
# which is accepted - the ECS API documents the field as taking either - so apply succeeds and the provider
# works. The problem arrives afterwards: ECS stores the ARN, so the next refresh reads an ARN back into
# state where the configuration says a name, the field cannot be updated in place, and every subsequent plan
# proposes replacing the capacity provider. That replacement then fails, because ECS refuses to delete a
# provider while the cluster's default strategy and a service's strategy still name it. The end state is a
# configuration that cannot be applied again, from a line that looked like it worked.
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
# Attaches the provider to the cluster and makes it the default, so a task run without a strategy of its own
# still lands on these instances.
#
# A separate resource rather than part of the cluster, which is what keeps the graph acyclic: the instances
# need the cluster name, the cluster needs the provider name, and the provider needs the group. It is also
# what makes destroy work in the right order - it holds the only link from the cluster to the provider, so
# Terraform removes the link before deleting the provider, and ECS rejects deleting a provider still linked.
#
# .name rather than .id. The template wrote aws_ecs_capacity_provider.ecs_ec2_capacity_provider.id, and this
# resource's id is its ARN - while PutClusterCapacityProviders documents capacityProviders and
# defaultCapacityProviderStrategy.capacityProvider as the provider's name, with no mention of an ARN being
# accepted (its cluster argument, on the same page, documents both - so the omission is the point). ECS reads
# the list back as names, so an ARN written here never matches what is returned and every plan proposes
# putting the same list again, forever. The ecs_service module makes the same correction in its strategy.
resource "aws_ecs_cluster_capacity_providers" "cluster_capacity_providers" {
  cluster_name       = var.cluster_name
  capacity_providers = concat([aws_ecs_capacity_provider.capacity_provider.name], var.additional_capacity_providers)
  default_capacity_provider_strategy {
    base              = var.default_strategy_base
    weight            = var.default_strategy_weight
    capacity_provider = aws_ecs_capacity_provider.capacity_provider.name
  }
}
