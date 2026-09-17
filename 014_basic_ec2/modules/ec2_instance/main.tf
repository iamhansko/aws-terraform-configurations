data "aws_ssm_parameter" "ami_id" {
  name = var.ami_ssm_parameter_name
}
resource "aws_security_group" "ec2_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks. Inline
# blocks are authoritative over the whole group, so any rule Terraform does not
# know about is reverted on the next apply; standalone resources are the
# provider's current recommendation and the safe default (rules.md F-2).
resource "aws_vpc_security_group_ingress_rule" "ec2_cidr_ingress" {
  for_each          = var.ingress_cidr_rules
  security_group_id = aws_security_group.ec2_security_group.id
  description       = "Port ${each.value.port} from ${each.key}"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr_block
}
resource "aws_vpc_security_group_ingress_rule" "ec2_source_group_ingress" {
  for_each                     = var.ingress_source_group_rules
  security_group_id            = aws_security_group.ec2_security_group.id
  description                  = "Port ${each.value.port} from ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = each.value.security_group_id
}
resource "aws_vpc_security_group_egress_rule" "ec2_egress" {
  security_group_id = aws_security_group.ec2_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# The role and instance profile only exist when policies were asked for, so an
# instance that needs no AWS access is launched without one (rules.md B-4).
resource "aws_iam_role" "ec2_iam_role" {
  count = length(var.iam_policy_arns) > 0 ? 1 : 0
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
resource "aws_iam_role_policy_attachment" "ec2_iam_role" {
  for_each   = length(var.iam_policy_arns) > 0 ? toset(var.iam_policy_arns) : toset([])
  role       = aws_iam_role.ec2_iam_role[0].name
  policy_arn = each.value
}
# aws_iam_instance_profile.role takes a single role name, not the list that
# CloudFormation's AWS::IAM::InstanceProfile Roles property accepts
# (rules.md A-3).
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  count = length(var.iam_policy_arns) > 0 ? 1 : 0
  role  = aws_iam_role.ec2_iam_role[0].name
}
resource "aws_instance" "ec2" {
  ami                  = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type        = var.instance_type
  key_name             = var.key_name
  iam_instance_profile = length(var.iam_policy_arns) > 0 ? aws_iam_instance_profile.ec2_instance_profile[0].name : null
  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  user_data                   = var.user_data
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  vpc_security_group_ids      = concat([aws_security_group.ec2_security_group.id], var.extra_security_group_ids)
  tags = {
    Name = var.name
  }
  # The instance profile's role must already carry its managed policies before
  # the instance boots, otherwise the bootstrap script's AWS calls fail with
  # AccessDenied (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.ec2_iam_role]
}
