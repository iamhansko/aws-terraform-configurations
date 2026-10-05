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
  ami_type       = var.custom_ami_id == null ? var.ami_type : null
  instance_types = var.instance_types
  capacity_type  = var.capacity_type
  # Whether a PodDisruptionBudget can hold this node group's update up. Left to the
  # caller rather than hardcoded true: with force the drain becomes a delete and every
  # budget on the cluster is bypassed, so a project about budgets has to be able to
  # turn it off.
  force_update_version = var.force_update_version
  labels               = var.labels
  node_role_arn        = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    desired_size = var.desired_size
    max_size     = var.max_size
    min_size     = var.min_size
  }
  # How many nodes the upgrade phase cordons and drains in parallel. EKS applies a
  # default of one when this block is absent; stating it makes the number reviewable and
  # gives the caller somewhere to raise it. EKS accepts exactly one of the two fields,
  # hence the null.
  update_config {
    max_unavailable            = var.update_max_unavailable_percentage == null ? var.update_max_unavailable : null
    max_unavailable_percentage = var.update_max_unavailable_percentage
  }
  subnet_ids = var.subnet_ids
  launch_template {
    id = aws_launch_template.eks_node_launch_template.id
    # latest_version follows the template automatically, so a template change and the
    # node group replacement it causes land in one apply. A pinned version splits them,
    # which is what lets a caller create a new version now and adopt it later
    # (rules.md B-4).
    version = var.launch_template_version == null ? aws_launch_template.eks_node_launch_template.latest_version : var.launch_template_version
  }
  # The node role must already carry AmazonEKSWorkerNodePolicy and friends
  # before EKS accepts the create call; node_role_arn alone doesn't order this
  # module after the attachments (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.eks_node_iam_role]
}
