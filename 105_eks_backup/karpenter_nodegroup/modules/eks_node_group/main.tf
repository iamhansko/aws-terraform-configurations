resource "aws_iam_role" "eks_node_iam_role" {
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
resource "aws_iam_role_policy_attachment" "eks_node_iam_role" {
  for_each   = toset(var.node_iam_policy_arns)
  role       = aws_iam_role.eks_node_iam_role.name
  policy_arn = each.value
}
# A launch template is always created, even when every customizable input is
# left at its default, so the node group has one stable place to attach a key
# pair, extra security groups, instance tags and IMDS settings. Deliberately
# omits subnet_ids and the instance profile: EKS rejects launch templates that
# set either, because the node group supplies them.
resource "aws_launch_template" "eks_node_launch_template" {
  # A prefix rather than a fixed name, which is what the _monolithic template used
  # ("gpu-nodegroup-lt"). A launch template name is unique per region, so the fixed
  # form makes the project undeployable twice - and the failure is an
  # InvalidLaunchTemplateName.AlreadyExistsException with nothing pointing at the
  # cause.
  name_prefix = "${var.node_group_name}-lt-"
  key_name    = var.key_name
  image_id    = var.custom_ami_id
  user_data   = var.custom_user_data == null ? null : base64encode(var.custom_user_data)
  # Named on the template rather than on the node group when a capacity reservation
  # is targeted. EKS rejects instance_types on the node group together with a launch
  # template that sets instance_type, and a reservation is for one exact type - so
  # the type has to come from the same place the reservation does.
  instance_type          = var.launch_template_instance_type
  vpc_security_group_ids = length(var.vpc_security_group_ids) > 0 ? var.vpc_security_group_ids : null

  # Only when a reservation is targeted. An empty capacity_reservation_specification
  # block is not the same as none: it sets the preference to "none", which stops the
  # instance from using any open reservation it would otherwise have drifted into.
  dynamic "capacity_reservation_specification" {
    for_each = var.capacity_reservation_id == null ? [] : [var.capacity_reservation_id]
    content {
      # capacity-reservations-only, as the _monolithic template had it: the instance
      # launches into the reservation or does not launch. The alternative, "open",
      # would fall back to ordinary On-Demand capacity - which is friendlier and
      # defeats the purpose, because the point of reserving GPU capacity is that
      # ordinary capacity may not be there.
      capacity_reservation_preference = var.capacity_reservation_preference
      capacity_reservation_target {
        capacity_reservation_id = capacity_reservation_specification.value
      }
    }
  }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = var.instance_metadata_http_put_response_hop_limit
  }
  tag_specifications {
    resource_type = "instance"
    tags = merge(
      { Name = "${var.node_group_name}-instance" },
      var.instance_tags,
    )
  }
}
resource "aws_eks_node_group" "eks_node_group" {
  node_group_name = var.node_group_name
  cluster_name    = var.cluster_name
  # EKS rejects ami_type alongside a launch template that carries its own
  # image_id: the AMI is then fully described by the launch template.
  ami_type = var.custom_ami_id == null ? var.ami_type : null
  # Null rather than an empty list when the launch template names the type. EKS
  # rejects a node group that sets instance_types together with a launch template
  # that sets instance_type, and an empty list is still a value.
  instance_types       = length(var.instance_types) > 0 ? var.instance_types : null
  capacity_type        = var.capacity_type
  force_update_version = true
  labels               = var.labels

  # Taints, as a map keyed by taint key. A map rather than a list because the keys are literals in the
  # caller's configuration and become part of the block's identity, while the values are ordinary data
  # (rules.md B-8).
  #
  # Worth being careful with on a node group that hosts addons: a NO_SCHEDULE taint keeps off it every
  # pod that does not tolerate the taint, and that includes CoreDNS, which is a Deployment rather than a
  # DaemonSet. A cluster whose only node group is tainted and whose CoreDNS has no toleration comes up
  # with no working DNS, and nothing reports it as an error.
  dynamic "taint" {
    for_each = var.taints
    content {
      key    = taint.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }
  node_role_arn = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    desired_size = var.desired_size
    max_size     = var.max_size
    min_size     = var.min_size
  }
  subnet_ids = var.subnet_ids
  launch_template {
    id      = aws_launch_template.eks_node_launch_template.id
    version = aws_launch_template.eks_node_launch_template.latest_version
  }
  # The node role must already carry AmazonEKSWorkerNodePolicy and friends
  # before EKS accepts the create call; node_role_arn alone doesn't order this
  # module after the attachments (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.eks_node_iam_role]
}
