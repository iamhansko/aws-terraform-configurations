# Generated from 101_ubuntu_xrdp/ubuntu_24_04.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
terraform {
  required_version = ">= 1.9"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Defaults to the provider chain (AWS_REGION)."
}
variable "stack_name" {
  type        = string
  default     = "ubuntu-24-04"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "password" {
  type    = string
  default = "Ubuntu1234!"
}
variable "inbound_from_anywhere" {
  type        = string
  default     = "True"
  description = "SecurityGroup Inbound Rule (Source 0.0.0.0/0)"
  validation {
    condition     = contains(["True", "False"], var.inbound_from_anywhere)
    error_message = "InboundFromAnywhere must be one of: True, False"
  }
}
variable "ami_id" {
  type        = string
  default     = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "ami_id" {
  name = var.ami_id
}
# --- Mappings / Conditions ---
locals {
  mappings = {
    RegionMapping = {
      "us-east-1" = {
        AmiId = "ami-0b6c6ebed2801a5cb"
      }
      "us-east-2" = {
        AmiId = "ami-06e3c045d79fd65d9"
      }
      "us-west-2" = {
        AmiId = "ami-0786adace1541ca80"
      }
      "ap-northeast-1" = {
        AmiId = "ami-0f65fc8c24ec8d2a1"
      }
      "ap-northeast-2" = {
        AmiId = "ami-0130d8d35bcd2d433"
      }
    }
    AzMapping = {
      a = {
        PublicSubnetCidr  = "10.0.0.0/24"
        PrivateSubnetCidr = "10.0.1.0/24"
      }
      b = {
        PublicSubnetCidr  = "10.0.2.0/24"
        PrivateSubnetCidr = "10.0.3.0/24"
      }
      c = {
        PublicSubnetCidr  = "10.0.4.0/24"
        PrivateSubnetCidr = "10.0.5.0/24"
      }
    }
  }
  stack_id                                  = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
  cond_security_group_inbound_from_anywhere = (var.inbound_from_anywhere == "True")
}
# --- Resources split out of composite CloudFormation resources ---
resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
# CloudFormation stores the generated private key in SSM at /ec2/keypair/<key-pair-id>; mirrored below.
resource "aws_ssm_parameter" "key_pair_private_key" {
  name  = "/ec2/keypair/${aws_key_pair.key_pair.key_pair_id}"
  type  = "SecureString"
  value = tls_private_key.key_pair.private_key_pem
}
resource "aws_iam_role_policy_attachment" "ubuntu_ec2_iam_role" {
  role       = aws_iam_role.ubuntu_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
# --- Resources ---
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "vpc"
  }
}
resource "aws_subnet" "public_subneta" {
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = local.mappings["AzMapping"]["a"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-a"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subneta_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subneta.id
}
resource "aws_route_table" "public_subnet_route_table" {
  tags = {
    Name = "public-rt"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = "igw"
  }
}
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
resource "aws_route" "public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id
  depends_on             = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT15M"
# #   }
# # }
resource "aws_instance" "ubuntu_ec2" {
  ami           = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type = "m5.2xlarge"
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = "ubuntu"
  }
  iam_instance_profile        = aws_iam_instance_profile.ubuntu_ec2_instance_profile.name
  user_data                   = <<EOT
#!/bin/bash
set -x

apt update -yq
apt upgrade -yq
apt install -yq git
apt install -yq python3 python3-pip python3-venv
ln -sf /usr/bin/python3 /usr/bin/python
cd /home/ubuntu

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "$${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt update -yq
apt install -yq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
usermod -aG docker ubuntu

echo "ubuntu:${var.password}" | chpasswd
usermod -aG sudo ubuntu
DEBIAN_FRONTEND=noninteractive apt install -yq ubuntu-desktop

# curl -fsSL https://raw.githubusercontent.com/abhilashiig/kiro-ide-linux-installation/main/clone-and-install-kiro.sh | bash

su - ubuntu << 'EOF'
mkdir ~/Desktop
cd ~/Desktop

echo '#!/bin/bash
export TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
export IAM_ROLE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/)
export CREDENTIALS=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/$IAM_ROLE)
export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.Token')
echo -e "\n"
echo -e "AWS_ACCESS_KEY_ID : $AWS_ACCESS_KEY_ID \n\nAWS_SECRET_ACCESS_KEY : $AWS_SECRET_ACCESS_KEY \n\nAWS_SESSION_TOKEN : $AWS_SESSION_TOKEN\n"

# source ./scripts/env.sh
' > ./scripts/env.sh
chmod +x ./scripts/env.sh
source ./scripts/env.sh
EOF

apt install -yq xrdp
systemctl enable --now xrdp
adduser xrdp ssl-cert
systemctl restart xrdp

mkdir -p /home/ubuntu/.venv
python -m venv /home/ubuntu/.venv
source /home/ubuntu/.venv/bin/activate
curl -LO https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz
tar -xvzf aws-cfn-bootstrap-py3-latest.tar.gz
ln -sf aws-cfn-bootstrap-2.0/init/ubuntu/cfn-hup /etc/init.d/cfn-hup
python -m pip install aws-cfn-bootstrap-py3-latest.tar.gz
cfn-signal -e $? --stack ${var.stack_name} --resource UbuntuEc2 --region ${data.aws_region.current.region}
deactivate
chown -R ubuntu:ubuntu /home/ubuntu/.venv
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.ubuntu_ec2_security_group.id]
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100
    delete_on_termination = true
    encrypted             = false
  }
}
resource "aws_security_group" "ubuntu_ec2_security_group" {
  description = "Security Group"
  name        = "ubuntu-sg"
  vpc_id      = aws_vpc.vpc.id
  dynamic "ingress" {
    for_each = local.cond_security_group_inbound_from_anywhere ? [1] : []
    content {
      protocol    = "tcp"
      from_port   = 3389
      to_port     = 3389
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  tags = {
    Name = "ubuntu-sg"
  }
}
resource "aws_iam_role" "ubuntu_ec2_iam_role" {
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
resource "aws_iam_instance_profile" "ubuntu_ec2_instance_profile" {
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here sends the literal string
  # ["terraform-..."] as roleName, which IAM rejects with a ValidationError
  # during apply, while terraform validate and plan both pass because the
  # attribute is a string either way (rules.md A-3).
  role = aws_iam_role.ubuntu_ec2_iam_role.name
}
# --- Outputs ---
# CloudFormation output: 01RdpUrl
output "out_01_rdp_url" {
  value = "${aws_instance.ubuntu_ec2.public_ip}:3389"
}
# CloudFormation output: 02Username
output "out_02_username" {
  value = "ubuntu"
}
# CloudFormation output: 03Password
output "out_03_password" {
  value = var.password
}
