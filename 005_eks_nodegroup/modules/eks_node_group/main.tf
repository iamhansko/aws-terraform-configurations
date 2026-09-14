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

resource "aws_launch_template" "app_launch_template" {
  name                   = "${var.node_group_name}-launchtemplate"
  key_name               = var.key_name
  vpc_security_group_ids = var.vpc_security_group_ids
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.node_group_name}-instance"
    }
  }
}

resource "aws_eks_node_group" "app_node_group" {
  node_group_name      = var.node_group_name
  ami_type             = var.ami_type
  instance_types       = var.instance_types
  capacity_type        = var.capacity_type
  cluster_name         = var.cluster_name
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
    id      = aws_launch_template.app_launch_template.id
    version = aws_launch_template.app_launch_template.latest_version
  }

  depends_on = [aws_iam_role_policy_attachment.eks_node_iam_role]
}
