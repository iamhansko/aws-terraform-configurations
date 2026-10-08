# Generated from 109_eks_cross_vpc_tgw/cross_vpc_ingress.yaml by tools/cfn2tf.
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
  default     = "cross-vpc-ingress"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "inbound_from_anywhere" {
  type        = string
  default     = "True"
  description = "SecurityGroup Inbound Rule (Source 0.0.0.0/0)"
  validation {
    condition     = contains(["True", "False"], var.inbound_from_anywhere)
    error_message = "InboundFromAnywhere must be one of: True, False"
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.36"
  description = "EKS Cluster Kubernetes Version (1.XX)"
  validation {
    condition     = contains(["1.32", "1.33", "1.34", "1.35", "1.36"], var.kubernetes_version)
    error_message = "KubernetesVersion must be one of: 1.32, 1.33, 1.34, 1.35, 1.36"
  }
}
variable "ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "ami_id" {
  name = var.ami_id
}
# --- Mappings / Conditions ---
locals {
  mappings = {
    NonRoutableAzMapping = {
      a = {
        ClusterSubnetCidr = "100.64.1.0/28"
        NodeSubnetCidr    = "100.64.16.0/20"
      }
      c = {
        ClusterSubnetCidr = "100.64.2.0/28"
        NodeSubnetCidr    = "100.64.32.0/20"
      }
    }
    VpcAAzMapping = {
      a = {
        PublicSubnetCidr  = "192.168.16.0/24"
        PrivateSubnetCidr = "192.168.17.0/24"
      }
      c = {
        PublicSubnetCidr  = "192.168.18.0/24"
        PrivateSubnetCidr = "192.168.19.0/24"
      }
    }
    VpcBAzMapping = {
      a = {
        PublicSubnetCidr  = "192.168.32.0/24"
        PrivateSubnetCidr = "192.168.33.0/24"
      }
      c = {
        PublicSubnetCidr  = "192.168.34.0/24"
        PrivateSubnetCidr = "192.168.35.0/24"
      }
    }
    ResourceNameMapping = {
      VpcA = {
        TagValue = "vpc-a"
        CrossVpc = "VpcB"
      }
      VpcB = {
        TagValue = "vpc-b"
        CrossVpc = "VpcA"
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
resource "aws_iam_role_policy_attachment" "eks_cluster_iam_role" {
  role       = aws_iam_role.eks_cluster_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
resource "aws_iam_role_policy_attachment" "eks_node_iam_role_0" {
  role       = aws_iam_role.eks_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
resource "aws_iam_role_policy_attachment" "eks_node_iam_role_1" {
  role       = aws_iam_role.eks_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
resource "aws_iam_role_policy_attachment" "eks_node_iam_role_2" {
  role       = aws_iam_role.eks_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
resource "aws_iam_role_policy_attachment" "eks_node_iam_role_3" {
  role       = aws_iam_role.eks_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy" "aws_load_balancer_controller_role" {
  name = "AWSLoadBalancerControllerPolicy"
  role = aws_iam_role.aws_load_balancer_controller_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["iam:CreateServiceLinkedRole"]
      Resource = "*"
      Condition = {
        StringEquals = {
          "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
        }
      }
      }, {
      Effect   = "Allow"
      Action   = ["ec2:*", "elasticloadbalancing:*"]
      Resource = "*"
      }, {
      Effect   = "Allow"
      Action   = ["cognito-idp:DescribeUserPoolClient", "acm:ListCertificates", "acm:DescribeCertificate", "iam:ListServerCertificates", "iam:GetServerCertificate", "waf-regional:GetWebACL", "waf-regional:GetWebACLForResource", "waf-regional:AssociateWebACL", "waf-regional:DisassociateWebACL", "wafv2:GetWebACL", "wafv2:GetWebACLForResource", "wafv2:AssociateWebACL", "wafv2:DisassociateWebACL", "shield:GetSubscriptionState", "shield:DescribeProtection", "shield:CreateProtection", "shield:DeleteProtection"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "vpc_a_ec2_iam_role" {
  role       = aws_iam_role.vpc_a_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_eks_access_policy_association" "vpc_a_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.vpc_a_eks_cluster.name
  principal_arn = aws_iam_role.vpc_a_ec2_iam_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}
resource "aws_iam_role_policy_attachment" "vpc_b_ec2_iam_role" {
  role       = aws_iam_role.vpc_b_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_eks_access_policy_association" "vpc_b_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.vpc_b_eks_cluster.name
  principal_arn = aws_iam_role.vpc_b_ec2_iam_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}
# --- Resources ---
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_vpc" "vpc_a" {
  cidr_block           = "192.168.16.0/20"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "vpc-a"
  }
}
resource "aws_vpc_ipv4_cidr_block_association" "vpc_a_secondary_cidr_block" {
  vpc_id     = aws_vpc.vpc_a.id
  cidr_block = "100.64.0.0/16"
}
resource "aws_internet_gateway" "vpc_a_internet_gateway" {
  tags = {
    Name = "vpc-a-igw"
  }
}
resource "aws_internet_gateway_attachment" "vpc_a_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.vpc_a_internet_gateway.id
  vpc_id              = aws_vpc.vpc_a.id
}
resource "aws_route_table" "vpc_a_public_route_table" {
  vpc_id = aws_vpc.vpc_a.id
  tags = {
    Name = "vpc-a-public-rt"
  }
}
resource "aws_route" "vpc_a_public_internet_route" {
  route_table_id         = aws_route_table.vpc_a_public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.vpc_a_internet_gateway.id
  depends_on             = [aws_internet_gateway_attachment.vpc_a_internet_gateway_attachment]
}
resource "aws_route" "vpc_a_public_peer_route" {
  route_table_id         = aws_route_table.vpc_a_public_route_table.id
  destination_cidr_block = aws_vpc.vpc_b.cidr_block
  transit_gateway_id     = aws_ec2_transit_gateway.transit_gateway.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_a_attachment]
}
resource "aws_subnet" "vpc_a_public_subneta" {
  vpc_id                  = aws_vpc.vpc_a.id
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = local.mappings["VpcAAzMapping"]["a"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name                     = "vpc-a-public-subnet-a"
    "kubernetes.io/role/elb" = "1"
  }
}
resource "aws_route_table_association" "vpc_a_public_subneta_route_table_association" {
  route_table_id = aws_route_table.vpc_a_public_route_table.id
  subnet_id      = aws_subnet.vpc_a_public_subneta.id
}
resource "aws_subnet" "vpc_a_public_subnetc" {
  vpc_id                  = aws_vpc.vpc_a.id
  availability_zone       = "${data.aws_region.current.region}c"
  cidr_block              = local.mappings["VpcAAzMapping"]["c"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name                     = "vpc-a-public-subnet-c"
    "kubernetes.io/role/elb" = "1"
  }
}
resource "aws_route_table_association" "vpc_a_public_subnetc_route_table_association" {
  route_table_id = aws_route_table.vpc_a_public_route_table.id
  subnet_id      = aws_subnet.vpc_a_public_subnetc.id
}
resource "aws_subnet" "vpc_a_private_subneta" {
  vpc_id            = aws_vpc.vpc_a.id
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = local.mappings["VpcAAzMapping"]["a"]["PrivateSubnetCidr"]
  tags = {
    Name                              = "vpc-a-private-subnet-a"
    "kubernetes.io/role/internal-elb" = "1"
  }
}
resource "aws_eip" "vpc_a_public_nat_gateway_eipa" {}
resource "aws_nat_gateway" "vpc_a_public_nat_gatewaya" {
  connectivity_type = "public"
  subnet_id         = aws_subnet.vpc_a_public_subneta.id
  allocation_id     = aws_eip.vpc_a_public_nat_gateway_eipa.allocation_id
  tags = {
    Name = "vpc-a-public-natgw-a"
  }
  depends_on = [aws_internet_gateway_attachment.vpc_a_internet_gateway_attachment]
}
resource "aws_nat_gateway" "vpc_a_private_nat_gatewaya" {
  connectivity_type = "private"
  subnet_id         = aws_subnet.vpc_a_private_subneta.id
  tags = {
    Name = "vpc-a-private-natgw-a"
  }
}
resource "aws_route_table" "vpc_a_private_route_tablea" {
  vpc_id = aws_vpc.vpc_a.id
  tags = {
    Name = "vpc-a-private-rt-a"
  }
}
resource "aws_route_table_association" "vpc_a_private_subneta_route_table_association" {
  route_table_id = aws_route_table.vpc_a_private_route_tablea.id
  subnet_id      = aws_subnet.vpc_a_private_subneta.id
}
resource "aws_route" "vpc_a_private_internet_routea" {
  route_table_id         = aws_route_table.vpc_a_private_route_tablea.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.vpc_a_public_nat_gatewaya.id
}
resource "aws_route" "vpc_a_private_peer_routea" {
  route_table_id         = aws_route_table.vpc_a_private_route_tablea.id
  destination_cidr_block = aws_vpc.vpc_b.cidr_block
  transit_gateway_id     = aws_ec2_transit_gateway.transit_gateway.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_a_attachment]
}
resource "aws_subnet" "vpc_a_private_subnetc" {
  vpc_id            = aws_vpc.vpc_a.id
  availability_zone = "${data.aws_region.current.region}c"
  cidr_block        = local.mappings["VpcAAzMapping"]["c"]["PrivateSubnetCidr"]
  tags = {
    Name                              = "vpc-a-private-subnet-c"
    "kubernetes.io/role/internal-elb" = "1"
  }
}
resource "aws_eip" "vpc_a_public_nat_gateway_eipc" {}
resource "aws_nat_gateway" "vpc_a_public_nat_gatewayc" {
  connectivity_type = "public"
  subnet_id         = aws_subnet.vpc_a_public_subnetc.id
  allocation_id     = aws_eip.vpc_a_public_nat_gateway_eipc.allocation_id
  tags = {
    Name = "vpc-a-public-natgw-c"
  }
  depends_on = [aws_internet_gateway_attachment.vpc_a_internet_gateway_attachment]
}
resource "aws_nat_gateway" "vpc_a_private_nat_gatewayc" {
  connectivity_type = "private"
  subnet_id         = aws_subnet.vpc_a_private_subnetc.id
  tags = {
    Name = "vpc-a-private-natgw-c"
  }
}
resource "aws_route_table" "vpc_a_private_route_tablec" {
  vpc_id = aws_vpc.vpc_a.id
  tags = {
    Name = "vpc-a-private-rt-c"
  }
}
resource "aws_route_table_association" "vpc_a_private_subnetc_route_table_association" {
  route_table_id = aws_route_table.vpc_a_private_route_tablec.id
  subnet_id      = aws_subnet.vpc_a_private_subnetc.id
}
resource "aws_route" "vpc_a_private_internet_routec" {
  route_table_id         = aws_route_table.vpc_a_private_route_tablec.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.vpc_a_public_nat_gatewayc.id
}
resource "aws_route" "vpc_a_private_peer_routec" {
  route_table_id         = aws_route_table.vpc_a_private_route_tablec.id
  destination_cidr_block = aws_vpc.vpc_b.cidr_block
  transit_gateway_id     = aws_ec2_transit_gateway.transit_gateway.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_a_attachment]
}
resource "aws_subnet" "vpc_a_cluster_subneta" {
  vpc_id            = aws_vpc.vpc_a.id
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = local.mappings["NonRoutableAzMapping"]["a"]["ClusterSubnetCidr"]
  tags = {
    Name = "vpc-a-cluster-subnet-a"
  }
  depends_on = [aws_vpc_ipv4_cidr_block_association.vpc_a_secondary_cidr_block]
}
resource "aws_subnet" "vpc_a_node_subneta" {
  vpc_id            = aws_vpc.vpc_a.id
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = local.mappings["NonRoutableAzMapping"]["a"]["NodeSubnetCidr"]
  tags = {
    Name = "vpc-a-node-subnet-a"
  }
  depends_on = [aws_vpc_ipv4_cidr_block_association.vpc_a_secondary_cidr_block]
}
resource "aws_route_table" "vpc_a_node_route_tablea" {
  vpc_id = aws_vpc.vpc_a.id
  tags = {
    Name = "vpc-a-node-rt-a"
  }
}
resource "aws_route_table_association" "vpc_a_node_subneta_route_table_association" {
  route_table_id = aws_route_table.vpc_a_node_route_tablea.id
  subnet_id      = aws_subnet.vpc_a_node_subneta.id
}
resource "aws_route" "vpc_a_node_internet_routea" {
  route_table_id         = aws_route_table.vpc_a_node_route_tablea.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.vpc_a_public_nat_gatewaya.id
}
resource "aws_route" "vpc_a_node_peer_routea" {
  route_table_id         = aws_route_table.vpc_a_node_route_tablea.id
  destination_cidr_block = aws_vpc.vpc_b.cidr_block
  nat_gateway_id         = aws_nat_gateway.vpc_a_private_nat_gatewaya.id
}
resource "aws_subnet" "vpc_a_cluster_subnetc" {
  vpc_id            = aws_vpc.vpc_a.id
  availability_zone = "${data.aws_region.current.region}c"
  cidr_block        = local.mappings["NonRoutableAzMapping"]["c"]["ClusterSubnetCidr"]
  tags = {
    Name = "vpc-a-cluster-subnet-c"
  }
  depends_on = [aws_vpc_ipv4_cidr_block_association.vpc_a_secondary_cidr_block]
}
resource "aws_subnet" "vpc_a_node_subnetc" {
  vpc_id            = aws_vpc.vpc_a.id
  availability_zone = "${data.aws_region.current.region}c"
  cidr_block        = local.mappings["NonRoutableAzMapping"]["c"]["NodeSubnetCidr"]
  tags = {
    Name = "vpc-a-node-subnet-c"
  }
  depends_on = [aws_vpc_ipv4_cidr_block_association.vpc_a_secondary_cidr_block]
}
resource "aws_route_table" "vpc_a_node_route_tablec" {
  vpc_id = aws_vpc.vpc_a.id
  tags = {
    Name = "vpc-a-node-rt-c"
  }
}
resource "aws_route_table_association" "vpc_a_node_subnetc_route_table_association" {
  route_table_id = aws_route_table.vpc_a_node_route_tablec.id
  subnet_id      = aws_subnet.vpc_a_node_subnetc.id
}
resource "aws_route" "vpc_a_node_internet_routec" {
  route_table_id         = aws_route_table.vpc_a_node_route_tablec.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.vpc_a_public_nat_gatewayc.id
}
resource "aws_route" "vpc_a_node_peer_routec" {
  route_table_id         = aws_route_table.vpc_a_node_route_tablec.id
  destination_cidr_block = aws_vpc.vpc_b.cidr_block
  nat_gateway_id         = aws_nat_gateway.vpc_a_private_nat_gatewayc.id
}
resource "aws_vpc" "vpc_b" {
  cidr_block           = "192.168.32.0/20"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "vpc-b"
  }
}
resource "aws_vpc_ipv4_cidr_block_association" "vpc_b_secondary_cidr_block" {
  vpc_id     = aws_vpc.vpc_b.id
  cidr_block = "100.64.0.0/16"
}
resource "aws_internet_gateway" "vpc_b_internet_gateway" {
  tags = {
    Name = "vpc-b-igw"
  }
}
resource "aws_internet_gateway_attachment" "vpc_b_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.vpc_b_internet_gateway.id
  vpc_id              = aws_vpc.vpc_b.id
}
resource "aws_route_table" "vpc_b_public_route_table" {
  vpc_id = aws_vpc.vpc_b.id
  tags = {
    Name = "vpc-b-public-rt"
  }
}
resource "aws_route" "vpc_b_public_internet_route" {
  route_table_id         = aws_route_table.vpc_b_public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.vpc_b_internet_gateway.id
  depends_on             = [aws_internet_gateway_attachment.vpc_b_internet_gateway_attachment]
}
resource "aws_route" "vpc_b_public_peer_route" {
  route_table_id         = aws_route_table.vpc_b_public_route_table.id
  destination_cidr_block = aws_vpc.vpc_a.cidr_block
  transit_gateway_id     = aws_ec2_transit_gateway.transit_gateway.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_b_attachment]
}
resource "aws_subnet" "vpc_b_public_subneta" {
  vpc_id                  = aws_vpc.vpc_b.id
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = local.mappings["VpcBAzMapping"]["a"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name = "vpc-b-public-subnet-a"
  }
}
resource "aws_route_table_association" "vpc_b_public_subneta_route_table_association" {
  route_table_id = aws_route_table.vpc_b_public_route_table.id
  subnet_id      = aws_subnet.vpc_b_public_subneta.id
}
resource "aws_subnet" "vpc_b_public_subnetc" {
  vpc_id                  = aws_vpc.vpc_b.id
  availability_zone       = "${data.aws_region.current.region}c"
  cidr_block              = local.mappings["VpcBAzMapping"]["c"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name = "vpc-b-public-subnet-c"
  }
}
resource "aws_route_table_association" "vpc_b_public_subnetc_route_table_association" {
  route_table_id = aws_route_table.vpc_b_public_route_table.id
  subnet_id      = aws_subnet.vpc_b_public_subnetc.id
}
resource "aws_subnet" "vpc_b_private_subneta" {
  vpc_id            = aws_vpc.vpc_b.id
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = local.mappings["VpcBAzMapping"]["a"]["PrivateSubnetCidr"]
  tags = {
    Name                              = "vpc-b-private-subnet-a"
    "kubernetes.io/role/internal-elb" = "1"
  }
}
resource "aws_eip" "vpc_b_public_nat_gateway_eipa" {}
resource "aws_nat_gateway" "vpc_b_public_nat_gatewaya" {
  connectivity_type = "public"
  subnet_id         = aws_subnet.vpc_b_public_subneta.id
  allocation_id     = aws_eip.vpc_b_public_nat_gateway_eipa.allocation_id
  tags = {
    Name = "vpc-b-public-natgw-a"
  }
  depends_on = [aws_internet_gateway_attachment.vpc_b_internet_gateway_attachment]
}
resource "aws_nat_gateway" "vpc_b_private_nat_gatewaya" {
  connectivity_type = "private"
  subnet_id         = aws_subnet.vpc_b_private_subneta.id
  tags = {
    Name = "vpc-b-private-natgw-a"
  }
}
resource "aws_route_table" "vpc_b_private_route_tablea" {
  vpc_id = aws_vpc.vpc_b.id
  tags = {
    Name = "vpc-b-private-rt-a"
  }
}
resource "aws_route_table_association" "vpc_b_private_subneta_route_table_association" {
  route_table_id = aws_route_table.vpc_b_private_route_tablea.id
  subnet_id      = aws_subnet.vpc_b_private_subneta.id
}
resource "aws_route" "vpc_b_private_internet_routea" {
  route_table_id         = aws_route_table.vpc_b_private_route_tablea.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.vpc_b_public_nat_gatewaya.id
}
resource "aws_route" "vpc_b_private_peer_routea" {
  route_table_id         = aws_route_table.vpc_b_private_route_tablea.id
  destination_cidr_block = aws_vpc.vpc_a.cidr_block
  transit_gateway_id     = aws_ec2_transit_gateway.transit_gateway.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_b_attachment]
}
resource "aws_subnet" "vpc_b_private_subnetc" {
  vpc_id            = aws_vpc.vpc_b.id
  availability_zone = "${data.aws_region.current.region}c"
  cidr_block        = local.mappings["VpcBAzMapping"]["c"]["PrivateSubnetCidr"]
  tags = {
    Name                              = "vpc-b-private-subnet-c"
    "kubernetes.io/role/internal-elb" = "1"
  }
}
resource "aws_eip" "vpc_b_public_nat_gateway_eipc" {}
resource "aws_nat_gateway" "vpc_b_public_nat_gatewayc" {
  connectivity_type = "public"
  subnet_id         = aws_subnet.vpc_b_public_subnetc.id
  allocation_id     = aws_eip.vpc_b_public_nat_gateway_eipc.allocation_id
  tags = {
    Name = "vpc-b-public-natgw-c"
  }
  depends_on = [aws_internet_gateway_attachment.vpc_b_internet_gateway_attachment]
}
resource "aws_nat_gateway" "vpc_b_private_nat_gatewayc" {
  connectivity_type = "private"
  subnet_id         = aws_subnet.vpc_b_private_subnetc.id
  tags = {
    Name = "vpc-b-private-natgw-c"
  }
}
resource "aws_route_table" "vpc_b_private_route_tablec" {
  vpc_id = aws_vpc.vpc_b.id
  tags = {
    Name = "vpc-b-private-rt-c"
  }
}
resource "aws_route_table_association" "vpc_b_private_subnetc_route_table_association" {
  route_table_id = aws_route_table.vpc_b_private_route_tablec.id
  subnet_id      = aws_subnet.vpc_b_private_subnetc.id
}
resource "aws_route" "vpc_b_private_internet_routec" {
  route_table_id         = aws_route_table.vpc_b_private_route_tablec.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.vpc_b_public_nat_gatewayc.id
}
resource "aws_route" "vpc_b_private_peer_routec" {
  route_table_id         = aws_route_table.vpc_b_private_route_tablec.id
  destination_cidr_block = aws_vpc.vpc_a.cidr_block
  transit_gateway_id     = aws_ec2_transit_gateway.transit_gateway.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_b_attachment]
}
resource "aws_subnet" "vpc_b_cluster_subneta" {
  vpc_id            = aws_vpc.vpc_b.id
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = local.mappings["NonRoutableAzMapping"]["a"]["ClusterSubnetCidr"]
  tags = {
    Name = "vpc-b-cluster-subnet-a"
  }
  depends_on = [aws_vpc_ipv4_cidr_block_association.vpc_b_secondary_cidr_block]
}
resource "aws_subnet" "vpc_b_node_subneta" {
  vpc_id            = aws_vpc.vpc_b.id
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = local.mappings["NonRoutableAzMapping"]["a"]["NodeSubnetCidr"]
  tags = {
    Name = "vpc-b-node-subnet-a"
  }
  depends_on = [aws_vpc_ipv4_cidr_block_association.vpc_b_secondary_cidr_block]
}
resource "aws_route_table" "vpc_b_node_route_tablea" {
  vpc_id = aws_vpc.vpc_b.id
  tags = {
    Name = "vpc-b-node-rt-a"
  }
}
resource "aws_route_table_association" "vpc_b_node_subneta_route_table_association" {
  route_table_id = aws_route_table.vpc_b_node_route_tablea.id
  subnet_id      = aws_subnet.vpc_b_node_subneta.id
}
resource "aws_route" "vpc_b_node_internet_routea" {
  route_table_id         = aws_route_table.vpc_b_node_route_tablea.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.vpc_b_public_nat_gatewaya.id
}
resource "aws_route" "vpc_b_node_peer_routea" {
  route_table_id         = aws_route_table.vpc_b_node_route_tablea.id
  destination_cidr_block = aws_vpc.vpc_a.cidr_block
  nat_gateway_id         = aws_nat_gateway.vpc_b_private_nat_gatewaya.id
}
resource "aws_subnet" "vpc_b_cluster_subnetc" {
  vpc_id            = aws_vpc.vpc_b.id
  availability_zone = "${data.aws_region.current.region}c"
  cidr_block        = local.mappings["NonRoutableAzMapping"]["c"]["ClusterSubnetCidr"]
  tags = {
    Name = "vpc-b-cluster-subnet-c"
  }
  depends_on = [aws_vpc_ipv4_cidr_block_association.vpc_b_secondary_cidr_block]
}
resource "aws_subnet" "vpc_b_node_subnetc" {
  vpc_id            = aws_vpc.vpc_b.id
  availability_zone = "${data.aws_region.current.region}c"
  cidr_block        = local.mappings["NonRoutableAzMapping"]["c"]["NodeSubnetCidr"]
  tags = {
    Name = "vpc-b-node-subnet-c"
  }
  depends_on = [aws_vpc_ipv4_cidr_block_association.vpc_b_secondary_cidr_block]
}
resource "aws_route_table" "vpc_b_node_route_tablec" {
  vpc_id = aws_vpc.vpc_b.id
  tags = {
    Name = "vpc-b-node-rt-c"
  }
}
resource "aws_route_table_association" "vpc_b_node_subnetc_route_table_association" {
  route_table_id = aws_route_table.vpc_b_node_route_tablec.id
  subnet_id      = aws_subnet.vpc_b_node_subnetc.id
}
resource "aws_route" "vpc_b_node_internet_routec" {
  route_table_id         = aws_route_table.vpc_b_node_route_tablec.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.vpc_b_public_nat_gatewayc.id
}
resource "aws_route" "vpc_b_node_peer_routec" {
  route_table_id         = aws_route_table.vpc_b_node_route_tablec.id
  destination_cidr_block = aws_vpc.vpc_a.cidr_block
  nat_gateway_id         = aws_nat_gateway.vpc_b_private_nat_gatewayc.id
}
resource "aws_ec2_transit_gateway" "transit_gateway" {
  description                     = "Vpc A <-> Vpc B"
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  tags = {
    Name = "tgw"
  }
}
resource "aws_ec2_transit_gateway_route_table" "transit_gateway_route_table" {
  transit_gateway_id = aws_ec2_transit_gateway.transit_gateway.id
  tags = {
    Name = "tgw-rt"
  }
}
resource "aws_ec2_transit_gateway_vpc_attachment" "transit_gateway_vpc_a_attachment" {
  transit_gateway_id = aws_ec2_transit_gateway.transit_gateway.id
  vpc_id             = aws_vpc.vpc_a.id
  subnet_ids         = [aws_subnet.vpc_a_private_subneta.id, aws_subnet.vpc_a_private_subnetc.id]
  tags = {
    Name = "tgw-${local.mappings["ResourceNameMapping"]["VpcA"]["TagValue"]}"
  }
}
resource "aws_ec2_transit_gateway_route_table_association" "transit_gateway_vpc_a_attachment_association" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_a_attachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.transit_gateway_route_table.id
}
resource "aws_ec2_transit_gateway_route" "transit_gateway_vpc_a_route" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.transit_gateway_route_table.id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_a_attachment.id
  destination_cidr_block         = aws_vpc.vpc_a.cidr_block
}
resource "aws_ec2_transit_gateway_vpc_attachment" "transit_gateway_vpc_b_attachment" {
  transit_gateway_id = aws_ec2_transit_gateway.transit_gateway.id
  vpc_id             = aws_vpc.vpc_b.id
  subnet_ids         = [aws_subnet.vpc_b_private_subneta.id, aws_subnet.vpc_b_private_subnetc.id]
  tags = {
    Name = "tgw-${local.mappings["ResourceNameMapping"]["VpcB"]["TagValue"]}"
  }
}
resource "aws_ec2_transit_gateway_route_table_association" "transit_gateway_vpc_b_attachment_association" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_b_attachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.transit_gateway_route_table.id
}
resource "aws_ec2_transit_gateway_route" "transit_gateway_vpc_b_route" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.transit_gateway_route_table.id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_b_attachment.id
  destination_cidr_block         = aws_vpc.vpc_b.cidr_block
}
resource "aws_eks_cluster" "vpc_a_eks_cluster" {
  version = var.kubernetes_version
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = false
    subnet_ids              = [aws_subnet.vpc_a_cluster_subneta.id, aws_subnet.vpc_a_cluster_subnetc.id]
  }
  role_arn = aws_iam_role.eks_cluster_iam_role.arn
  kubernetes_network_config {
    ip_family         = "ipv4"
    service_ipv4_cidr = "172.20.0.0/16"
  }
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-vpc-a-eks-cluster"
}
resource "aws_eks_addon" "vpc_a_vpc_cni_add_on" {
  addon_name   = "vpc-cni"
  cluster_name = aws_eks_cluster.vpc_a_eks_cluster.name
}
resource "aws_eks_addon" "vpc_a_kube_proxy_add_on" {
  addon_name   = "kube-proxy"
  cluster_name = aws_eks_cluster.vpc_a_eks_cluster.name
}
resource "aws_eks_addon" "vpc_a_core_dns_add_on" {
  addon_name   = "coredns"
  cluster_name = aws_eks_cluster.vpc_a_eks_cluster.name
}
resource "aws_eks_addon" "vpc_a_pod_identity_agent_addon" {
  addon_name   = "eks-pod-identity-agent"
  cluster_name = aws_eks_cluster.vpc_a_eks_cluster.name
}
resource "aws_eks_pod_identity_association" "vpc_a_aws_load_balancer_controller_role_pod_identity_association" {
  cluster_name    = aws_eks_cluster.vpc_a_eks_cluster.name
  namespace       = "kube-system"
  role_arn        = aws_iam_role.aws_load_balancer_controller_role.arn
  service_account = "aws-load-balancer-controller"
}
resource "aws_eks_node_group" "vpc_a_core_node_group" {
  node_group_name      = "core-nodegroup"
  ami_type             = "AL2023_x86_64_STANDARD"
  instance_types       = ["t3.medium"]
  capacity_type        = "ON_DEMAND"
  cluster_name         = aws_eks_cluster.vpc_a_eks_cluster.name
  force_update_version = true
  node_role_arn        = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }
  subnet_ids = [aws_subnet.vpc_a_node_subneta.id, aws_subnet.vpc_a_node_subnetc.id]
}
resource "aws_eks_cluster" "vpc_b_eks_cluster" {
  version = var.kubernetes_version
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = false
    subnet_ids              = [aws_subnet.vpc_b_cluster_subneta.id, aws_subnet.vpc_b_cluster_subnetc.id]
  }
  role_arn = aws_iam_role.eks_cluster_iam_role.arn
  kubernetes_network_config {
    ip_family         = "ipv4"
    service_ipv4_cidr = "172.20.0.0/16"
  }
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-vpc-b-eks-cluster"
}
resource "aws_eks_addon" "vpc_b_vpc_cni_add_on" {
  addon_name   = "vpc-cni"
  cluster_name = aws_eks_cluster.vpc_b_eks_cluster.name
}
resource "aws_eks_addon" "vpc_b_kube_proxy_add_on" {
  addon_name   = "kube-proxy"
  cluster_name = aws_eks_cluster.vpc_b_eks_cluster.name
}
resource "aws_eks_addon" "vpc_b_core_dns_add_on" {
  addon_name   = "coredns"
  cluster_name = aws_eks_cluster.vpc_b_eks_cluster.name
}
resource "aws_eks_addon" "vpc_b_pod_identity_agent_addon" {
  addon_name   = "eks-pod-identity-agent"
  cluster_name = aws_eks_cluster.vpc_b_eks_cluster.name
}
resource "aws_eks_pod_identity_association" "vpc_b_aws_load_balancer_controller_role_pod_identity_association" {
  cluster_name    = aws_eks_cluster.vpc_b_eks_cluster.name
  namespace       = "kube-system"
  role_arn        = aws_iam_role.aws_load_balancer_controller_role.arn
  service_account = "aws-load-balancer-controller"
}
resource "aws_eks_node_group" "vpc_b_core_node_group" {
  node_group_name      = "core-nodegroup"
  ami_type             = "AL2023_x86_64_STANDARD"
  instance_types       = ["t3.medium"]
  capacity_type        = "ON_DEMAND"
  cluster_name         = aws_eks_cluster.vpc_b_eks_cluster.name
  force_update_version = true
  node_role_arn        = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }
  subnet_ids = [aws_subnet.vpc_b_node_subneta.id, aws_subnet.vpc_b_node_subnetc.id]
}
resource "aws_iam_role" "eks_cluster_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["eks.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
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
resource "aws_iam_role" "aws_load_balancer_controller_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT15M"
# #   }
# # }
resource "aws_instance" "vpc_a_ec2" {
  ami           = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type = "t3.medium"
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = "vpc-a-ec2"
  }
  iam_instance_profile        = aws_iam_instance_profile.vpc_a_ec2_instance_profile.name
  user_data                   = <<EOT
#!/bin/bash
dnf update -yq
dnf install -yq git
dnf groupinstall -yq "Development Tools"

export VSC_VERSION=$(curl -s https://api.github.com/repos/coder/code-server/releases/latest | jq -r '.tag_name | ltrimstr("v")')
wget https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
tar -xzf code-server-$VSC_VERSION-linux-amd64.tar.gz
mv code-server-$VSC_VERSION-linux-amd64 /usr/local/lib/code-server
ln -s /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server
mkdir -p /home/ec2-user/.config/code-server
cat <<EOF > /home/ec2-user/.config/code-server/config.yaml
bind-addr: 0.0.0.0:8000
auth: none
cert: false
EOF
chown -R ec2-user:ec2-user /home/ec2-user/.config
cat <<EOF > /etc/systemd/system/code-server.service
[Unit]
Description=VS Code Server
After=network.target
[Service]
Type=simple
User=ec2-user
ExecStart=/usr/local/bin/code-server --config /home/ec2-user/.config/code-server/config.yaml /home/ec2-user
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable code-server
systemctl start code-server

sudo -Eu ec2-user bash << 'EOF'
cd /home/ec2-user
mkdir -p /home/ec2-user/bin
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.33.3/2025-08-03/bin/linux/amd64/kubectl
chmod +x kubectl
mv kubectl /home/ec2-user/bin/kubectl
export PATH=/home/ec2-user/bin:$PATH
echo "export PATH=/home/ec2-user/bin:$PATH" >> ~/.bashrc
echo "alias k=kubectl" >> ~/.bashrc
echo "complete -o default -F __start_kubectl k" >> ~/.bashrc
echo "source <(kubectl completion bash)" >> ~/.bashrc
exec bash

aws eks update-kubeconfig --name ${aws_eks_cluster.vpc_a_eks_cluster.name} --region ${data.aws_region.current.region}

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource VpcAEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.vpc_a_public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.vpc_a_ec2_security_group.id, aws_eks_cluster.vpc_a_eks_cluster.vpc_config[0].cluster_security_group_id]
  depends_on                  = [aws_eks_node_group.vpc_a_core_node_group, aws_eks_node_group.vpc_b_core_node_group, aws_ec2_transit_gateway_route.transit_gateway_vpc_a_route, aws_ec2_transit_gateway_route.transit_gateway_vpc_b_route]
}
resource "aws_security_group" "vpc_a_ec2_security_group" {
  description = "Security Group"
  name        = "vpc-a-ec2-sg"
  vpc_id      = aws_vpc.vpc_a.id
  dynamic "ingress" {
    for_each = local.cond_security_group_inbound_from_anywhere ? [1] : []
    content {
      protocol    = "tcp"
      from_port   = 8000
      to_port     = 8000
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  tags = {
    Name = "vpc-a-ec2-sg"
  }
}
resource "aws_iam_role" "vpc_a_ec2_iam_role" {
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
resource "aws_iam_instance_profile" "vpc_a_ec2_instance_profile" {
  role = jsonencode([aws_iam_role.vpc_a_ec2_iam_role.name])
}
resource "aws_eks_access_entry" "vpc_a_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.vpc_a_eks_cluster.name
  principal_arn = aws_iam_role.vpc_a_ec2_iam_role.arn
  type          = "STANDARD"
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT15M"
# #   }
# # }
resource "aws_instance" "vpc_b_ec2" {
  ami           = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type = "t3.medium"
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = "vpc-b-ec2"
  }
  iam_instance_profile        = aws_iam_instance_profile.vpc_b_ec2_instance_profile.name
  user_data                   = <<EOT
#!/bin/bash
dnf update -yq
dnf install -yq git
dnf groupinstall -yq "Development Tools"

export VSC_VERSION=$(curl -s https://api.github.com/repos/coder/code-server/releases/latest | jq -r '.tag_name | ltrimstr("v")')
wget https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
tar -xzf code-server-$VSC_VERSION-linux-amd64.tar.gz
mv code-server-$VSC_VERSION-linux-amd64 /usr/local/lib/code-server
ln -s /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server
mkdir -p /home/ec2-user/.config/code-server
cat <<EOF > /home/ec2-user/.config/code-server/config.yaml
bind-addr: 0.0.0.0:8000
auth: none
cert: false
EOF
chown -R ec2-user:ec2-user /home/ec2-user/.config
cat <<EOF > /etc/systemd/system/code-server.service
[Unit]
Description=VS Code Server
After=network.target
[Service]
Type=simple
User=ec2-user
ExecStart=/usr/local/bin/code-server --config /home/ec2-user/.config/code-server/config.yaml /home/ec2-user
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable code-server
systemctl start code-server

sudo -Eu ec2-user bash << 'EOF'
cd /home/ec2-user
mkdir -p /home/ec2-user/bin
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.33.3/2025-08-03/bin/linux/amd64/kubectl
chmod +x kubectl
mv kubectl /home/ec2-user/bin/kubectl
export PATH=/home/ec2-user/bin:$PATH
echo "export PATH=/home/ec2-user/bin:$PATH" >> ~/.bashrc
echo "alias k=kubectl" >> ~/.bashrc
echo "complete -o default -F __start_kubectl k" >> ~/.bashrc
echo "source <(kubectl completion bash)" >> ~/.bashrc
exec bash

aws eks update-kubeconfig --name ${aws_eks_cluster.vpc_b_eks_cluster.name} --region ${data.aws_region.current.region}

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource VpcBEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.vpc_b_public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.vpc_b_ec2_security_group.id, aws_eks_cluster.vpc_b_eks_cluster.vpc_config[0].cluster_security_group_id]
  depends_on                  = [aws_eks_node_group.vpc_a_core_node_group, aws_eks_node_group.vpc_b_core_node_group, aws_ec2_transit_gateway_route.transit_gateway_vpc_a_route, aws_ec2_transit_gateway_route.transit_gateway_vpc_b_route]
}
resource "aws_security_group" "vpc_b_ec2_security_group" {
  description = "Security Group"
  name        = "vpc-b-ec2-sg"
  vpc_id      = aws_vpc.vpc_b.id
  dynamic "ingress" {
    for_each = local.cond_security_group_inbound_from_anywhere ? [1] : []
    content {
      protocol    = "tcp"
      from_port   = 8000
      to_port     = 8000
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  tags = {
    Name = "vpc-b-ec2-sg"
  }
}
resource "aws_iam_role" "vpc_b_ec2_iam_role" {
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
resource "aws_iam_instance_profile" "vpc_b_ec2_instance_profile" {
  role = jsonencode([aws_iam_role.vpc_b_ec2_iam_role.name])
}
resource "aws_eks_access_entry" "vpc_b_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.vpc_b_eks_cluster.name
  principal_arn = aws_iam_role.vpc_b_ec2_iam_role.arn
  type          = "STANDARD"
}
resource "aws_ssm_association" "vpc_a_ec2_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 600
  targets {
    key    = "InstanceIds"
    values = [aws_instance.vpc_a_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << 'SSMEOF'\nexport HOME=/home/ec2-user\ncd $HOME\n\ncurl --silent --location \"https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz\" | tar xz -C /tmp\nsudo mv /tmp/eksctl /usr/local/bin\n\ncurl -fsSL -o /home/ec2-user/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4\nchmod 700 /home/ec2-user/get_helm.sh\n/home/ec2-user/get_helm.sh\nrm /home/ec2-user/get_helm.sh\n\nhelm repo add eks https://aws.github.io/eks-charts\nhelm repo update eks\nhelm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --wait \\\n--set clusterName=${aws_eks_cluster.vpc_a_eks_cluster.name} \\\n--set serviceAccount.name=aws-load-balancer-controller \\\n--set region=${data.aws_region.current.region} \\\n--set vpcId=${aws_vpc.vpc_a.id}\nsleep 60\n\nmkdir -p /home/ec2-user/manifests\necho 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: nginx\nspec:\n  selector:\n    matchLabels:\n      app: nginx\n  replicas: 5\n  template:\n    metadata:\n      labels:\n        app: nginx\n    spec:\n      containers:\n      - image: nginx:latest\n        imagePullPolicy: Always\n        name: nginx\n        ports:\n        - containerPort: 80\n---\napiVersion: v1\nkind: Service\nmetadata:\n  name: nginx\nspec:\n  ports:\n    - port: 80\n      targetPort: 80\n      protocol: TCP\n  type: ClusterIP\n  selector:\n    app: nginx\n---\napiVersion: networking.k8s.io/v1\nkind: Ingress\nmetadata:\n  name: nginx\n  annotations:\n    alb.ingress.kubernetes.io/scheme: internet-facing\n    alb.ingress.kubernetes.io/target-type: ip\n    alb.ingress.kubernetes.io/security-groups: ${aws_security_group.vpc_a_alb_security_group.id}, ${aws_eks_cluster.vpc_a_eks_cluster.vpc_config[0].cluster_security_group_id}\nspec:\n  ingressClassName: alb\n  rules:\n    - http:\n        paths:\n        - path: /\n          pathType: Prefix\n          backend:\n            service:\n              name: nginx\n              port:\n                number: 80' > /home/ec2-user/manifests/web.yaml\nkubectl apply -f /home/ec2-user/manifests/web.yaml\n\necho \"# Cross-VPC\n\n# VPC A - EKS Cluster Ingress (ALB)\ncurl http://${aws_lb.vpc_a_alb.dns_name}\n\n# VPC B - EKS Cluster Ingress (ALB)\ncurl http://${aws_lb.vpc_b_alb.dns_name}\n\" > /home/ec2-user/README.md\nSSMEOF\n"])
  }
  depends_on = [aws_instance.vpc_a_ec2]
}
resource "aws_ssm_association" "vpc_b_ec2_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 600
  targets {
    key    = "InstanceIds"
    values = [aws_instance.vpc_b_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << 'SSMEOF'\nexport HOME=/home/ec2-user\ncd $HOME\n\ncurl --silent --location \"https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz\" | tar xz -C /tmp\nsudo mv /tmp/eksctl /usr/local/bin\n\ncurl -fsSL -o /home/ec2-user/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4\nchmod 700 /home/ec2-user/get_helm.sh\n/home/ec2-user/get_helm.sh\nrm /home/ec2-user/get_helm.sh\n\nhelm repo add eks https://aws.github.io/eks-charts\nhelm repo update eks\nhelm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --wait \\\n--set clusterName=${aws_eks_cluster.vpc_b_eks_cluster.name} \\\n--set serviceAccount.name=aws-load-balancer-controller \\\n--set region=${data.aws_region.current.region} \\\n--set vpcId=${aws_vpc.vpc_b.id}\nsleep 60\n\nmkdir -p /home/ec2-user/manifests\necho 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: nginx\nspec:\n  selector:\n    matchLabels:\n      app: nginx\n  replicas: 5\n  template:\n    metadata:\n      labels:\n        app: nginx\n    spec:\n      containers:\n      - image: nginx:latest\n        imagePullPolicy: Always\n        name: nginx\n        ports:\n        - containerPort: 80\n---\napiVersion: v1\nkind: Service\nmetadata:\n  name: nginx\nspec:\n  ports:\n    - port: 80\n      targetPort: 80\n      protocol: TCP\n  type: ClusterIP\n  selector:\n    app: nginx\n---\napiVersion: networking.k8s.io/v1\nkind: Ingress\nmetadata:\n  name: nginx\n  annotations:\n    alb.ingress.kubernetes.io/scheme: internal\n    alb.ingress.kubernetes.io/target-type: ip\n    alb.ingress.kubernetes.io/security-groups: ${aws_security_group.vpc_b_alb_security_group.id}, ${aws_eks_cluster.vpc_b_eks_cluster.vpc_config[0].cluster_security_group_id}\nspec:\n  ingressClassName: alb\n  rules:\n    - http:\n        paths:\n        - path: /\n          pathType: Prefix\n          backend:\n            service:\n              name: nginx\n              port:\n                number: 80' > /home/ec2-user/manifests/web.yaml\nkubectl apply -f /home/ec2-user/manifests/web.yaml\n\necho \"# Cross-VPC\n\n# VPC A - EKS Cluster Ingress (ALB)\ncurl http://${aws_lb.vpc_a_alb.dns_name}\n\n# VPC B - EKS Cluster Ingress (ALB)\ncurl http://${aws_lb.vpc_b_alb.dns_name}\n\" > /home/ec2-user/README.md\nSSMEOF\n"])
  }
  depends_on = [aws_instance.vpc_b_ec2]
}
resource "aws_lb" "vpc_a_alb" {
  load_balancer_type = "application"
  subnets            = [aws_subnet.vpc_a_public_subneta.id, aws_subnet.vpc_a_public_subnetc.id]
  security_groups    = [aws_vpc.vpc_a.default_security_group_id]
  tags = {
    "elbv2.k8s.aws/cluster"    = aws_eks_cluster.vpc_a_eks_cluster.name
    "ingress.k8s.aws/resource" = "LoadBalancer"
    "ingress.k8s.aws/stack"    = "default/nginx"
  }
  internal = false
}
resource "aws_security_group" "vpc_a_alb_security_group" {
  description = "Security Group"
  name        = "vpc-a-alb-sg"
  dynamic "ingress" {
    for_each = local.cond_security_group_inbound_from_anywhere ? [1] : []
    content {
      protocol    = "tcp"
      from_port   = 80
      to_port     = 80
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  vpc_id = aws_vpc.vpc_a.id
  tags = {
    Name = "vpc-a-alb-sg"
  }
}
resource "aws_lb" "vpc_b_alb" {
  load_balancer_type = "application"
  subnets            = [aws_subnet.vpc_b_private_subneta.id, aws_subnet.vpc_b_private_subnetc.id]
  security_groups    = [aws_vpc.vpc_b.default_security_group_id]
  tags = {
    "elbv2.k8s.aws/cluster"    = aws_eks_cluster.vpc_b_eks_cluster.name
    "ingress.k8s.aws/resource" = "LoadBalancer"
    "ingress.k8s.aws/stack"    = "default/nginx"
  }
  internal = true
}
resource "aws_security_group" "vpc_b_alb_security_group" {
  description = "Security Group"
  name        = "vpc-b-alb-sg"
  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = [aws_vpc.vpc_a.cidr_block]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = [aws_vpc.vpc_b.cidr_block]
  }
  vpc_id = aws_vpc.vpc_b.id
  tags = {
    Name = "vpc-b-alb-sg"
  }
}
# --- Outputs ---
# CloudFormation output: VpcAEc2
output "vpc_a_ec2" {
  value       = "http://${aws_instance.vpc_a_ec2.public_ip}:8000"
  description = "Public IP Address of the VS Code (VPC A)"
}
# CloudFormation output: VpcBEc2
output "vpc_b_ec2" {
  value       = "http://${aws_instance.vpc_b_ec2.public_ip}:8000"
  description = "Public IP Address of the VS Code (VPC B)"
}
