# An ECS Managed Instances capacity provider, and the two roles and one security group it cannot work
# without.
#
# One module, because the three pieces only make sense together: ECS assumes the infrastructure role to
# launch instances, passes the instance role to them, and puts them in this security group. None of them is
# shared with anything else (rules.md C-2).
locals {
  assume_ec2 = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
# --- Infrastructure role: what ECS uses to create, tag and terminate the instances ------------------------
resource "aws_iam_role" "infrastructure" {
  name_prefix = "${trimsuffix(substr(var.name, 0, 26), "-")}-infra-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "infrastructure" {
  role       = aws_iam_role.infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForManagedInstances"
}
# --- Instance role: what the ECS agent on each managed instance runs as -----------------------------------
#
# The name must begin with ecsInstanceRole. That is not a convention: the infrastructure role's managed policy
# grants iam:PassRole only on arn:aws:iam::*:role/ecsInstanceRole*, so a role named anything else is created
# without complaint and then cannot be handed to an instance - the capacity provider is accepted and never
# launches anything. The _monolithic template got this right with "ecsInstanceRole-<uuid slice>"; name_prefix
# keeps the prefix and drops the uuid. No path either, because the PassRole resource has none.
resource "aws_iam_role" "instance" {
  name_prefix        = var.instance_role_name_prefix
  assume_role_policy = local.assume_ec2
}
resource "aws_iam_role_policy_attachment" "instance" {
  for_each   = toset(var.instance_role_policy_arns)
  role       = aws_iam_role.instance.name
  policy_arn = each.value
}
# A single role name, not the list CloudFormation's AWS::IAM::InstanceProfile Roles property takes (rules.md
# A-3). The profile carries the same prefix, so both read as belonging to ECS in the console.
resource "aws_iam_instance_profile" "instance" {
  name_prefix = var.instance_role_name_prefix
  role        = aws_iam_role.instance.name
}
# --- Security group for the instances ---------------------------------------------------------------------
resource "aws_security_group" "instances" {
  name        = var.security_group_name
  description = "Security Group for the ECS Managed Instances"
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# The one rule this group needs, which the _monolithic template's group did not have: it declared no rules at
# all, and Terraform removes the allow-all egress AWS puts on a new group. An instance in it could not reach
# the ECS endpoint to register, so the capacity provider launched instances that never joined the cluster and
# the services' tasks stayed PROVISIONING. Tasks get their own ENIs in their own groups (awsvpc), so nothing
# needs ingress here.
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.instances.id
  description       = "ECS agent registration, image pulls and EFS mounts through the NAT gateways"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# --- Capacity provider ------------------------------------------------------------------------------------
resource "aws_ecs_capacity_provider" "managed_instances" {
  name = var.name
  # Required for managed instances, and the property the CloudFormation conversion dropped: ClusterName came
  # through as a commented-out TODO, which the provider rejects for a managed_instances_provider.
  cluster = var.cluster_name
  managed_instances_provider {
    infrastructure_role_arn = aws_iam_role.infrastructure.arn
    # How long an instance with no tasks is kept before ECS terminates it. Zero, as the _monolithic template
    # had it: terminate as soon as it is idle. This is also what makes the destroy-time drain finish quickly.
    infrastructure_optimization {
      scale_in_after = var.scale_in_after_seconds
    }
    # The other property the conversion dropped (AutoRepairConfiguration, also a TODO). ENABLED replaces an
    # instance ECS finds impaired instead of leaving its tasks on it.
    auto_repair_configuration {
      actions_status = var.auto_repair_actions_status
    }
    instance_launch_template {
      ec2_instance_profile_arn = aws_iam_instance_profile.instance.arn
      capacity_option_type     = var.capacity_option_type
      monitoring               = var.monitoring
      network_configuration {
        subnets         = var.subnet_ids
        security_groups = [aws_security_group.instances.id]
      }
      storage_configuration {
        storage_size_gib = var.storage_size_gib
      }
      instance_requirements {
        vcpu_count {
          min = var.vcpu_count.min
          max = var.vcpu_count.max
        }
        memory_mib {
          min = var.memory_mib.min
          max = var.memory_mib.max
        }
      }
    }
  }
  tags = {
    Name = var.name
  }
  # Three things ECS needs in place before it will launch anything, none of which the references above order
  # this after (rules.md D-1): the infrastructure role's policy, the instance role's policies - an instance
  # that boots without AmazonEC2ContainerServiceforEC2Role never registers - and the egress rule.
  #
  # The order matters at least as much in reverse. On destroy this goes first, while the infrastructure role
  # can still terminate the instances; deleting that role's policy first would leave ECS unable to clean up.
  depends_on = [
    aws_iam_role_policy_attachment.infrastructure,
    aws_iam_role_policy_attachment.instance,
    aws_vpc_security_group_egress_rule.all_outbound,
  ]
}
