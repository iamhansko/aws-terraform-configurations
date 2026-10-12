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
  # A prefix rather than a fixed name. A launch template name has to be unique in the region, while
  # the node group name it is derived from only has to be unique in its cluster - and the root calls
  # this module once per cluster with the same node group name on purpose, as the _monolithic template
  # named both of its node groups. A fixed "<node group>-launchtemplate" therefore let the first
  # cluster's node group claim the name and made the second one fail with
  # InvalidLaunchTemplateName.AlreadyExistsException. Nothing looks the template up by name (the node
  # group below takes its ID), so the generated suffix costs nothing. The _monolithic template had no
  # launch template at all, so the collision came in with the module split.
  name_prefix            = "${var.node_group_name}-launchtemplate-"
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
    tags = {
      Name = "${var.node_group_name}-instance"
    }
  }
  lifecycle {
    # A launch template created before the switch to name_prefix carries a fixed name. name and
    # name_prefix both force replacement, the node group's launch_template.id forces replacement too,
    # and EKS does not let a node group change to a different launch template after creation. Without
    # this, applying over an existing deployment would replace the launch template and then the whole
    # node group - every node, and the pods and volumes on it - for a change that alters nothing on
    # the nodes. The prefix only matters for a template that does not exist yet, and ignoring the name
    # leaves that case untouched. Replacing a template on purpose is a terraform apply -replace.
    ignore_changes = [name, name_prefix]
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
}
