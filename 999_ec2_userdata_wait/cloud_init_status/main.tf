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

  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_a_id

  additional_user_data = <<-EOT
    date > /home/ec2-user/COMMAND0.md
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
      cloud-init status --wait
      sleep 10
      date > /home/ec2-user/COMMAND1.md
      EOT
  }
}
