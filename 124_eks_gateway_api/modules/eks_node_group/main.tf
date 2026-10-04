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
# One resource with for_each rather than the four numbered attachments the conversion produced, so the policy
# list is an input the caller can extend without editing this module (rules.md B-7). toset is safe here because
# the ARNs are literal strings known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "eks_node_iam_role" {
  for_each   = toset(var.node_iam_policy_arns)
  role       = aws_iam_role.eks_node_iam_role.name
  policy_arn = each.value
}
# A launch template is always created, even when every customizable input is left at its default, so the node
# group has one stable place to attach a key pair and IMDS settings. The _monolithic template attached no key
# pair to its nodes at all, which left them reachable only through SSM Session Manager - fine, but it also
# meant the generated key pair existed solely for the workbench.
#
# Deliberately omits subnet_ids and the instance profile: EKS rejects launch templates that set either,
# because the node group supplies them.
resource "aws_launch_template" "eks_node_launch_template" {
  name                   = "${var.node_group_name}-launchtemplate"
  key_name               = var.key_name
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
}
resource "aws_eks_node_group" "eks_node_group" {
  node_group_name      = var.node_group_name
  cluster_name         = var.cluster_name
  ami_type             = var.ami_type
  instance_types       = var.instance_types
  capacity_type        = var.capacity_type
  force_update_version = var.force_update_version
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
  # The node role must already carry AmazonEKSWorkerNodePolicy and friends before EKS accepts the create call;
  # node_role_arn alone doesn't order this after the attachments (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.eks_node_iam_role]
}
