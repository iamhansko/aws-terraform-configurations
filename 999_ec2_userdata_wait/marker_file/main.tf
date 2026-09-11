data "aws_region" "current" {}

data "aws_ssm_parameter" "amazon_linux2023_ami_id" {
  name = var.amazon_linux2023_ami_id
}

module "network" {
  source = "../modules/network"
}

module "key_pair" {
  source   = "../modules/key_pair"
  key_name = var.key_pair_name
}

module "vscode_ec2" {
  source = "../modules/vscode_ec2"

  name          = var.vscode_instance_name
  instance_type = var.vscode_instance_type
  ami_id        = data.aws_ssm_parameter.amazon_linux2023_ami_id.insecure_value
  key_name      = module.key_pair.key_name

  vpc_id           = module.network.vpc_id
  subnet_id        = module.network.public_subnet_a_id
  marker_file_path = var.marker_file_path

  additional_user_data = <<-EOT
    date > /home/ec2-user/BEFORE_MARK.md
    sleep 120
    date > /home/ec2-user/AFTER_MARK.md
  EOT
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
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      sleep 10
      date > /home/ec2-user/COMMAND1.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_association_1
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
      until [ -f ${module.vscode_ec2.marker_file_path}/vscode_association_1 ]; do sleep 10; done
      sleep 20
      date > /home/ec2-user/COMMAND2.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_association_2
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
      until [ -f ${module.vscode_ec2.marker_file_path}/vscode_association_2 ]; do sleep 10; done
      sleep 30
      date > /home/ec2-user/COMMAND3.md
      EOT
  }
}
