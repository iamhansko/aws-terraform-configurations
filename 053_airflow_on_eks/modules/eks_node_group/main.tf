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
  name                   = "${var.node_group_name}-launchtemplate"
  key_name               = var.key_name
  image_id               = var.custom_ami_id
  user_data              = var.custom_user_data == null ? null : base64encode(var.custom_user_data)
  vpc_security_group_ids = length(var.vpc_security_group_ids) > 0 ? var.vpc_security_group_ids : null
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = var.instance_metadata_http_put_response_hop_limit
  }
  # Only when a size is asked for. Without a mapping the node keeps the AMI's own root volume, which
  # on the EKS-optimized AMIs is 20 GiB - fine for a node that runs a few add-ons, tight for one that
  # pulls Spark images several gigabytes each. /dev/xvda is the root device name on the AL2023 and
  # AL2 EKS AMIs alike, so this resizes the root rather than adding a second disk (rules.md B-4).
  dynamic "block_device_mappings" {
    for_each = var.root_volume_size == null ? [] : [var.root_volume_size]
    content {
      device_name = "/dev/xvda"
      ebs {
        volume_size           = block_device_mappings.value
        volume_type           = "gp3"
        delete_on_termination = true
        encrypted             = true
      }
    }
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
  ami_type             = var.custom_ami_id == null ? var.ami_type : null
  instance_types       = var.instance_types
  capacity_type        = var.capacity_type
  force_update_version = true
  labels               = var.labels
  node_role_arn        = aws_iam_role.eks_node_iam_role.arn
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

  lifecycle {
    # The cluster autoscaler owns the group's size once it exists: it moves the Auto Scaling group's
    # desired capacity, and EKS reports that back as this node group's desired_size. Without this,
    # every plan after a scale-up proposes putting the old number back, and applying it scales the
    # cluster down under the pods that caused the scale-up. desired_size therefore only sets the
    # starting size; min_size and max_size stay Terraform's (the same split as rules.md E-8, on an
    # AWS resource rather than a manifest).
    ignore_changes = [scaling_config[0].desired_size]
  }
}
