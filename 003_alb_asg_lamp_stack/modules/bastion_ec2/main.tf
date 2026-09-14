data "aws_ssm_parameter" "ami_id" {
  name = var.ami_ssm_parameter_name
}

resource "aws_security_group" "bastion_ec2_security_group" {
  description = "Security Group for Bastion EC2 SSH Connection"
  name        = "bastion-sg"
  vpc_id      = var.vpc_id

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion-sg"
  }
}

resource "aws_iam_role" "bastion_ec2_iam_role" {
  name = "Ec2PowerUserRole"
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

resource "aws_iam_role_policy_attachment" "bastion_ec2_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.bastion_ec2_iam_role.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "bastion_ec2_instance_profile" {
  name = "Ec2PowerUserProfile"
  role = aws_iam_role.bastion_ec2_iam_role.name
}

resource "aws_instance" "bastion_ec2" {
  ami                         = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type               = var.instance_type
  key_name                    = var.key_name
  iam_instance_profile        = aws_iam_instance_profile.bastion_ec2_instance_profile.name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_ec2_security_group.id]

  tags = {
    Name = "stem-bastion-ec2"
  }

  # The instance role must have its managed policy attached before EKS/AWS
  # APIs will accept it via the instance profile (rules.md #12).
  depends_on = [aws_iam_role_policy_attachment.bastion_ec2_iam_role]
}
