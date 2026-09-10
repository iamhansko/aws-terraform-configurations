variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Defaults to the provider chain (AWS_REGION)."
}

data "aws_region" "current" {}

variable "amazon_linux2023_ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "Resolved by the aws_ssm_parameter data source"
}

data "aws_ssm_parameter" "amazon_linux2023_ami_id" {
  name = var.amazon_linux2023_ami_id
}

module "network" {
  source = "./modules/network"
}

module "key_pair" {
  source   = "./modules/key_pair"
  key_name = "ec2-keypair"
}

locals {
  marker_file_path = "/run/terraform"
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name          = "vscode"
  instance_type = "t3.small"
  ami_id        = data.aws_ssm_parameter.amazon_linux2023_ami_id.insecure_value
  key_name      = module.key_pair.key_name

  vpc_id           = module.network.vpc_id
  subnet_id        = module.network.public_subnet_a_id
  marker_file_path = local.marker_file_path
}

resource "aws_ssm_association" "vscode_association_1" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 300
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      until [ -f ${local.marker_file_path}/userdata ]; do sleep 10; done
      sleep 10
      date > /home/ec2-user/COMMAND1.md
      touch ${local.marker_file_path}/vscode_association_1
      EOT
  }
}

resource "aws_ssm_association" "vscode_association_2" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 300
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  depends_on = [
    aws_ssm_association.vscode_association_1
  ]
  parameters = {
    commands = <<-EOT
      until [ -f ${local.marker_file_path}/vscode_association_1 ]; do sleep 10; done
      sleep 20
      date > /home/ec2-user/COMMAND2.md
      touch ${local.marker_file_path}/vscode_association_2
      EOT
  }
}

resource "aws_ssm_association" "vscode_association_3" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 300
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  depends_on = [
    aws_ssm_association.vscode_association_2
  ]
  parameters = {
    commands = <<-EOT
      until [ -f ${local.marker_file_path}/vscode_association_2 ]; do sleep 10; done
      sleep 30
      date > /home/ec2-user/COMMAND3.md
      EOT
  }
}
