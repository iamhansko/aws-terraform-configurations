# Generated from 026_centralized_outbound_routing_to_the_internet/cross_vpc_with_tgw.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
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
  default     = "cross-vpc-with-tgw"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "amazon_linux2023_ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "amazon_linux2023_ami_id" {
  name = var.amazon_linux2023_ami_id
}
# --- Mappings / Conditions ---
locals {
  stack_id = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
}
# --- Resources split out of composite CloudFormation resources ---
resource "aws_iam_role_policy_attachment" "bastion_ec2_iam_role_0" {
  role       = aws_iam_role.bastion_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_iam_role_policy_attachment" "bastion_ec2_iam_role_1" {
  role       = aws_iam_role.bastion_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
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
resource "aws_iam_role_policy" "custom_resource_lambda_iam_role" {
  name = "TransitGatewayDescribePolicy"
  role = aws_iam_role.custom_resource_lambda_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:*"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "custom_resource_lambda_iam_role" {
  role       = aws_iam_role.custom_resource_lambda_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
data "archive_file" "custom_resource_lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/custom_resource_lambda_function/index.py"
  output_path = "${path.module}/build/custom_resource_lambda_function.zip"
}
# --- Resources ---
resource "aws_vpc" "egress_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "egress-vpc"
  }
}
resource "aws_subnet" "egress_public_subnet_a" {
  vpc_id                  = aws_vpc.egress_vpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "${data.aws_region.current.region}a"
  map_public_ip_on_launch = true
  tags = {
    Name = "egress-public-sn-a"
  }
}
resource "aws_subnet" "egress_public_subnet_b" {
  vpc_id                  = aws_vpc.egress_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${data.aws_region.current.region}b"
  map_public_ip_on_launch = true
  tags = {
    Name = "egress-public-sn-b"
  }
}
resource "aws_subnet" "egress_peering_subnet_a" {
  vpc_id            = aws_vpc.egress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${data.aws_region.current.region}a"
  tags = {
    Name = "egress-peering-sn-a"
  }
}
resource "aws_subnet" "egress_peering_subnet_b" {
  vpc_id            = aws_vpc.egress_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${data.aws_region.current.region}b"
  tags = {
    Name = "egress-peering-sn-b"
  }
}
resource "aws_subnet" "egress_firewall_subnet_a" {
  vpc_id            = aws_vpc.egress_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "${data.aws_region.current.region}a"
  tags = {
    Name = "egress-firewall-sn-a"
  }
}
resource "aws_subnet" "egress_firewall_subnet_b" {
  vpc_id            = aws_vpc.egress_vpc.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = "${data.aws_region.current.region}b"
  tags = {
    Name = "egress-firewall-sn-b"
  }
}
resource "aws_internet_gateway" "egress_igw" {
  tags = {
    Name = "egress-igw"
  }
}
resource "aws_internet_gateway_attachment" "egress_igw_attach" {
  vpc_id              = aws_vpc.egress_vpc.id
  internet_gateway_id = aws_internet_gateway.egress_igw.id
}
resource "aws_route_table" "egress_public_rt" {
  vpc_id = aws_vpc.egress_vpc.id
  tags = {
    Name = "egress-public-rt"
  }
}
resource "aws_route" "egress_public_route" {
  route_table_id         = aws_route_table.egress_public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.egress_igw.id
}
resource "aws_route" "egress_public_to_tgw_route" {
  route_table_id         = aws_route_table.egress_public_rt.id
  destination_cidr_block = aws_vpc.app_vpc.cidr_block
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.egress_vpc_tgw_attachment]
}
resource "aws_route_table_association" "egress_public_subnet_a_rt_association" {
  subnet_id      = aws_subnet.egress_public_subnet_a.id
  route_table_id = aws_route_table.egress_public_rt.id
}
resource "aws_route_table_association" "egress_public_subnet_b_rt_association" {
  subnet_id      = aws_subnet.egress_public_subnet_b.id
  route_table_id = aws_route_table.egress_public_rt.id
}
resource "aws_eip" "egress_vpc_natgw_a_elastic_ip" {}
resource "aws_nat_gateway" "egress_vpc_b_natgw_a" {
  allocation_id = aws_eip.egress_vpc_natgw_a_elastic_ip.allocation_id
  subnet_id     = aws_subnet.egress_public_subnet_a.id
  tags = {
    Name = "egress-natgw-a"
  }
}
resource "aws_route_table" "egress_vpc_priv_a_rt" {
  tags = {
    Name = "egress-priv-rt-a"
  }
  vpc_id = aws_vpc.egress_vpc.id
}
resource "aws_route_table_association" "egress_vpc_priv_a_rt_association" {
  route_table_id = aws_route_table.egress_vpc_priv_a_rt.id
  subnet_id      = aws_subnet.egress_peering_subnet_a.id
}
resource "aws_route" "egress_private_subnet_a_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.egress_vpc_b_natgw_a.id
  route_table_id         = aws_route_table.egress_vpc_priv_a_rt.id
}
resource "aws_eip" "egress_vpc_natgw_b_elastic_ip" {}
resource "aws_nat_gateway" "egress_vpc_b_natgw_b" {
  allocation_id = aws_eip.egress_vpc_natgw_b_elastic_ip.allocation_id
  subnet_id     = aws_subnet.egress_public_subnet_b.id
  tags = {
    Name = "egress-natgw-b"
  }
}
resource "aws_route_table" "egress_vpc_priv_b_rt" {
  tags = {
    Name = "egress-priv-rt-b"
  }
  vpc_id = aws_vpc.egress_vpc.id
}
resource "aws_route_table_association" "egress_vpc_priv_b_rt_association" {
  route_table_id = aws_route_table.egress_vpc_priv_b_rt.id
  subnet_id      = aws_subnet.egress_peering_subnet_b.id
}
resource "aws_route" "egress_private_subnet_b_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.egress_vpc_b_natgw_b.id
  route_table_id         = aws_route_table.egress_vpc_priv_b_rt.id
}
resource "aws_vpc" "app_vpc" {
  cidr_block           = "172.16.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "app-vpc"
  }
}
resource "aws_subnet" "app_private_subnet_a" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = "172.16.0.0/24"
  availability_zone = "${data.aws_region.current.region}a"
  tags = {
    Name = "app-private-sn-a"
  }
}
resource "aws_subnet" "app_private_subnet_b" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = "172.16.1.0/24"
  availability_zone = "${data.aws_region.current.region}b"
  tags = {
    Name = "app-private-sn-b"
  }
}
resource "aws_route_table" "app_rt" {
  vpc_id = aws_vpc.app_vpc.id
  tags = {
    Name = "app-rt"
  }
}
resource "aws_route" "app_to_tgw_route" {
  route_table_id         = aws_route_table.app_rt.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.app_vpc_tgw_attachment]
}
resource "aws_route_table_association" "app_private_subnet_a_rt_association" {
  subnet_id      = aws_subnet.app_private_subnet_a.id
  route_table_id = aws_route_table.app_rt.id
}
resource "aws_route_table_association" "app_private_subnet_b_rt_association" {
  subnet_id      = aws_subnet.app_private_subnet_b.id
  route_table_id = aws_route_table.app_rt.id
}
resource "aws_ec2_transit_gateway" "tgw" {
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  auto_accept_shared_attachments  = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
}
resource "aws_ec2_transit_gateway_vpc_attachment" "egress_vpc_tgw_attachment" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = aws_vpc.egress_vpc.id
  subnet_ids         = [aws_subnet.egress_peering_subnet_a.id, aws_subnet.egress_peering_subnet_b.id]
  tags = {
    Name = "tgw-egress"
  }
}
resource "aws_ec2_transit_gateway_vpc_attachment" "app_vpc_tgw_attachment" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = aws_vpc.app_vpc.id
  subnet_ids         = [aws_subnet.app_private_subnet_a.id, aws_subnet.app_private_subnet_b.id]
  tags = {
    Name = "tgw-app"
  }
}
resource "aws_ec2_transit_gateway_route" "tgw_static_route" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.egress_vpc_tgw_attachment.id
  transit_gateway_route_table_id = jsondecode(aws_lambda_invocation.tgw_default_route_table.result)["DefaultRouteTableId"]
}
resource "aws_networkfirewall_firewall" "network_firewall" {
  name                = "firewall"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.firewall_policy.id
  vpc_id              = aws_vpc.egress_vpc.id
  subnet_mapping {
    subnet_id = aws_subnet.egress_firewall_subnet_a.id
  }
  subnet_mapping {
    subnet_id = aws_subnet.egress_firewall_subnet_b.id
  }
  delete_protection                 = false
  subnet_change_protection          = false
  firewall_policy_change_protection = false
}
resource "aws_networkfirewall_firewall_policy" "firewall_policy" {
  name = "firewall-policy"
  firewall_policy {
    stateless_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.firewall_stateless_icmp_block.arn
      priority     = 1
    }
    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.firewall_stateful_dns_block.arn
    }
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]
  }
}
resource "aws_networkfirewall_rule_group" "firewall_stateless_icmp_block" {
  capacity = 100
  name     = "icmp-block-stateless"
  type     = "STATELESS"
  rule_group {
    rules_source {
      stateless_rules_and_custom_actions {
        stateless_rule {
          rule_definition {
            match_attributes {
              source {
                address_definition = "0.0.0.0/0"
              }
              destination {
                address_definition = "0.0.0.0/0"
              }
              protocols = [1]
            }
            actions = ["aws:drop"]
          }
          priority = 1
        }
      }
    }
  }
}
resource "aws_networkfirewall_rule_group" "firewall_stateful_dns_block" {
  capacity = 100
  name     = "dns-block-stateful"
  type     = "STATEFUL"
  rule_group {
    rules_source {
      rules_string = "drop udp any any -> any 53 (msg:\"Drop DNS UDP egress\"; sid:1000001;)\ndrop tcp any any -> any 53 (msg:\"Drop DNS TCP egress\"; sid:1000002;)\n"
    }
  }
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT2M"
# #   }
# # }
resource "aws_instance" "bastion_ec2" {
  instance_type          = "t3.medium"
  key_name               = aws_key_pair.key_pair.key_name
  ami                    = data.aws_ssm_parameter.amazon_linux2023_ami_id.insecure_value
  subnet_id              = aws_subnet.app_private_subnet_a.id
  vpc_security_group_ids = [aws_vpc.app_vpc.default_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.bastion_ec2_instance_profile.name
  tags = {
    Name = "app-bastion"
  }
  user_data  = <<EOT
#!/bin/bash
dnf update -yq
dnf install -yq bind-utils

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource BastionEc2 --region ${data.aws_region.current.region}
EOT
  depends_on = [aws_ec2_transit_gateway_route.tgw_static_route]
}
resource "aws_iam_role" "bastion_ec2_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ec2.amazonaws.com"]
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_instance_profile" "bastion_ec2_instance_profile" {
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here sends the literal string
  # ["terraform-..."] as roleName, which IAM rejects with a ValidationError
  # during apply, while terraform validate and plan both pass because the
  # attribute is a string either way (rules.md A-3).
  role = aws_iam_role.bastion_ec2_iam_role.name
}
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_lambda_invocation" "tgw_default_route_table" {
  function_name = aws_lambda_function.custom_resource_lambda_function.arn
  input = jsonencode({
    TransitGatewayId = aws_ec2_transit_gateway.tgw.id
  })
}
resource "aws_iam_role" "custom_resource_lambda_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_lambda_function" "custom_resource_lambda_function" {
  handler          = "index.lambda_handler"
  role             = aws_iam_role.custom_resource_lambda_iam_role.arn
  runtime          = "python3.13"
  timeout          = 60
  filename         = data.archive_file.custom_resource_lambda_function.output_path
  source_code_hash = data.archive_file.custom_resource_lambda_function.output_base64sha256
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-custom-resource-lambda-function"
}
