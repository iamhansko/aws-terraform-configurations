# Generated from 000_deprecated/ec2.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
terraform {
  required_version = ">= 1.5"
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
  default     = "ec2"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Mappings / Conditions ---
locals {
  mappings = {
    RegionMap = {
      "us-east-1" = {
        AmazonLinux2023 = "ami-0182f373e66f89c85"
      }
      "ap-northeast-2" = {
        AmazonLinux2023 = "ami-0023481579962abd4"
      }
    }
    ResourceMap = {
      Vpc = {
        Name      = "stem-vpc"
        CidrBlock = "10.1.0.0/16"
      }
      PublicSubnet = {
        Name = "stem-public"
      }
      PrivateSubnet = {
        Name = "stem-private"
      }
      InternetGateway = {
        Name = "stem-igw"
      }
      NatGateway = {
        Name = "stem-natgw"
      }
      PublicEc2 = {
        Name         = "stem-public-ec2"
        InstanceType = "t3.small"
      }
      PrivateEc2 = {
        Name         = "stem-private-ec2"
        InstanceType = "t3.small"
      }
    }
  }
  stack_id = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
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
# --- Resources ---
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_vpc" "vpc" {
  cidr_block = local.mappings["ResourceMap"]["Vpc"]["CidrBlock"]
  tags = {
    Name = local.mappings["ResourceMap"]["Vpc"]["Name"]
  }
}
resource "aws_subnet" "public_subnet_a" {
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = element([for __i in range(4) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 0)
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PublicSubnet"]["Name"], "a"])
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_subnet" "public_subnet_b" {
  availability_zone = "${data.aws_region.current.region}b"
  cidr_block        = element([for __i in range(4) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 1)
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PublicSubnet"]["Name"], "b"])
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_subnet" "private_subnet_a" {
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = element([for __i in range(4) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 2)
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PrivateSubnet"]["Name"], "a"])
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_subnet" "private_subnet_b" {
  availability_zone = "${data.aws_region.current.region}b"
  cidr_block        = element([for __i in range(4) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 3)
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PrivateSubnet"]["Name"], "b"])
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = local.mappings["ResourceMap"]["InternetGateway"]["Name"]
  }
}
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
resource "aws_eip" "nat_gateway_a_elastic_ip" {}
resource "aws_nat_gateway" "nat_gateway_a" {
  allocation_id = aws_eip.nat_gateway_a_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_a.id
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["NatGateway"]["Name"], "a"])
  }
}
resource "aws_eip" "nat_gateway_b_elastic_ip" {}
resource "aws_nat_gateway" "nat_gateway_b" {
  allocation_id = aws_eip.nat_gateway_b_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_b.id
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["NatGateway"]["Name"], "b"])
  }
}
resource "aws_route_table" "public_subnet_route_table" {
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PublicSubnet"]["Name"], "rt"])
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}
resource "aws_route_table_association" "public_subnet_b_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_b.id
}
resource "aws_route" "public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id
}
resource "aws_route_table" "private_subnet_a_route_table" {
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PrivateSubnet"]["Name"], "a", "rt"])
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "private_subnet_a_route_table_association" {
  route_table_id = aws_route_table.private_subnet_a_route_table.id
  subnet_id      = aws_subnet.private_subnet_a.id
}
resource "aws_route" "private_subnet_a_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_a.id
  route_table_id         = aws_route_table.private_subnet_a_route_table.id
}
resource "aws_route_table" "private_subnet_b_route_table" {
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PrivateSubnet"]["Name"], "b", "rt"])
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "private_subnet_b_route_table_association" {
  route_table_id = aws_route_table.private_subnet_b_route_table.id
  subnet_id      = aws_subnet.private_subnet_b.id
}
resource "aws_route" "private_subnet_b_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_b.id
  route_table_id         = aws_route_table.private_subnet_b_route_table.id
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT15M"
# #   }
# # }
resource "aws_instance" "public_ec2" {
  ami           = local.mappings["RegionMap"][data.aws_region.current.region]["AmazonLinux2023"]
  instance_type = local.mappings["ResourceMap"]["PublicEc2"]["InstanceType"]
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = local.mappings["ResourceMap"]["PublicEc2"]["Name"]
  }
  user_data                   = <<EOT
#!/bin/bash
su - ec2-user <<'EOF'
sudo dnf update -y
sudo dnf install -y git
cd /home/ec2-user
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
export NVM_DIR="/home/ec2-user/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
nvm install 20
git clone https://github.com/iamhansko/find-different-color.git
cd /home/ec2-user/find-different-color
npm install
/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource PublicEc2 --region ${data.aws_region.current.region}
npm run start
EOF
EOT
  subnet_id                   = aws_subnet.public_subnet_a.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.public_ec2_security_group.id]
}
resource "aws_security_group" "public_ec2_security_group" {
  description = "Security Group for Public EC2 SSH Connection"
  name        = "public-ec2-sg"
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 3000
    protocol    = "tcp"
    to_port     = 3000
  }
  vpc_id = aws_vpc.vpc.id
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT15M"
# #   }
# # }
resource "aws_instance" "private_ec2" {
  ami           = local.mappings["RegionMap"][data.aws_region.current.region]["AmazonLinux2023"]
  instance_type = local.mappings["ResourceMap"]["PrivateEc2"]["InstanceType"]
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = local.mappings["ResourceMap"]["PrivateEc2"]["Name"]
  }
  user_data              = <<EOT
#!/bin/bash
su - ec2-user <<'EOF'
sudo dnf update -y
sudo dnf install -y git
cd /home/ec2-user
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
export NVM_DIR="/home/ec2-user/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
nvm install 20
git clone https://github.com/iamhansko/find-different-color.git
cd /home/ec2-user/find-different-color
npm install
/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource PrivateEc2 --region ${data.aws_region.current.region}
npm run start
EOF
EOT
  subnet_id              = aws_subnet.private_subnet_a.id
  vpc_security_group_ids = [aws_security_group.private_ec2_security_group.id]
}
resource "aws_security_group" "private_ec2_security_group" {
  description = "Security Group for Private EC2 SSH Connection"
  name        = "private-ec2-sg"
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.public_ec2_security_group.id]
  }
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.public_ec2_security_group.id]
  }
  vpc_id = aws_vpc.vpc.id
}
