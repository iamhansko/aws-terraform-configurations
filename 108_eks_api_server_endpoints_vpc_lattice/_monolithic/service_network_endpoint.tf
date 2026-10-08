# Generated from 108_eks_api_server_endpoints_vpc_lattice/service_network_endpoint.yaml by tools/cfn2tf.
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
  default     = "service-network-endpoint"
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
    AzMapping = {
      a = {
        PublicSubnetCidr  = "10.1.0.0/24"
        PrivateSubnetCidr = "10.1.2.0/24"
      }
      c = {
        PublicSubnetCidr  = "10.1.1.0/24"
        PrivateSubnetCidr = "10.1.3.0/24"
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
data "archive_file" "lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/lambda_function/index.py"
  output_path = "${path.module}/build/lambda_function.zip"
}
resource "aws_iam_role_policy_attachment" "lambda_iam_role_0" {
  role       = aws_iam_role.lambda_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "lambda_iam_role_1" {
  role       = aws_iam_role.lambda_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}
resource "aws_iam_role_policy_attachment" "vs_code_ec2_iam_role" {
  role       = aws_iam_role.vs_code_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_eks_access_policy_association" "vs_code_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.vs_code_ec2_iam_role.arn
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
resource "aws_vpc" "cluster_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "cluster-vpc"
  }
}
resource "aws_subnet" "cluster_public_subneta" {
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = local.mappings["AzMapping"]["a"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name = "cluster-public-subnet-a"
  }
  vpc_id = aws_vpc.cluster_vpc.id
}
resource "aws_route_table_association" "cluster_public_subneta_route_table_association" {
  route_table_id = aws_route_table.cluster_public_subnet_route_table.id
  subnet_id      = aws_subnet.cluster_public_subneta.id
}
resource "aws_subnet" "cluster_public_subnetc" {
  availability_zone       = "${data.aws_region.current.region}c"
  cidr_block              = local.mappings["AzMapping"]["c"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name = "cluster-public-subnet-c"
  }
  vpc_id = aws_vpc.cluster_vpc.id
}
resource "aws_route_table_association" "cluster_public_subnetc_route_table_association" {
  route_table_id = aws_route_table.cluster_public_subnet_route_table.id
  subnet_id      = aws_subnet.cluster_public_subnetc.id
}
resource "aws_route_table" "cluster_public_subnet_route_table" {
  vpc_id = aws_vpc.cluster_vpc.id
  tags = {
    Name = "cluster-public-rt"
  }
}
resource "aws_internet_gateway" "cluster_internet_gateway" {
  tags = {
    Name = "cluster-igw"
  }
}
resource "aws_internet_gateway_attachment" "cluster_vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.cluster_internet_gateway.id
  vpc_id              = aws_vpc.cluster_vpc.id
}
resource "aws_route" "cluster_public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.cluster_internet_gateway.id
  route_table_id         = aws_route_table.cluster_public_subnet_route_table.id
  depends_on             = [aws_internet_gateway_attachment.cluster_vpc_internet_gateway_attachment]
}
resource "aws_subnet" "cluster_private_subneta" {
  vpc_id            = aws_vpc.cluster_vpc.id
  cidr_block        = local.mappings["AzMapping"]["a"]["PrivateSubnetCidr"]
  availability_zone = "${data.aws_region.current.region}a"
  tags = {
    Name = "cluster-private-subnet-a"
  }
}
resource "aws_route_table_association" "cluster_private_subneta_route_table_association" {
  route_table_id = aws_route_table.cluster_private_subnet_route_table.id
  subnet_id      = aws_subnet.cluster_private_subneta.id
}
resource "aws_subnet" "cluster_private_subnetc" {
  vpc_id            = aws_vpc.cluster_vpc.id
  cidr_block        = local.mappings["AzMapping"]["c"]["PrivateSubnetCidr"]
  availability_zone = "${data.aws_region.current.region}c"
  tags = {
    Name = "cluster-private-subnet-c"
  }
}
resource "aws_route_table_association" "cluster_private_subnetc_route_table_association" {
  route_table_id = aws_route_table.cluster_private_subnet_route_table.id
  subnet_id      = aws_subnet.cluster_private_subnetc.id
}
resource "aws_route_table" "cluster_private_subnet_route_table" {
  vpc_id = aws_vpc.cluster_vpc.id
  tags = {
    Name = "cluster-private-rt"
  }
}
resource "aws_route" "cluster_private_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.cluster_nat_gateway.id
  route_table_id         = aws_route_table.cluster_private_subnet_route_table.id
}
resource "aws_eip" "cluster_natgateway_elastic_ipa" {}
resource "aws_eip" "cluster_natgateway_elastic_ipc" {}
resource "aws_nat_gateway" "cluster_nat_gateway" {
  vpc_id            = aws_vpc.cluster_vpc.id
  availability_mode = "regional"
  availability_zone_address {
    availability_zone = "${data.aws_region.current.region}a"
    allocation_ids    = [aws_eip.cluster_natgateway_elastic_ipa.allocation_id]
  }
  availability_zone_address {
    availability_zone = "${data.aws_region.current.region}c"
    allocation_ids    = [aws_eip.cluster_natgateway_elastic_ipc.allocation_id]
  }
  tags = {
    Name = "cluster-regional-natgw"
  }
  depends_on = [aws_internet_gateway_attachment.cluster_vpc_internet_gateway_attachment]
}
resource "aws_eks_cluster" "eks_cluster" {
  version = var.kubernetes_version
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = false
    subnet_ids              = [aws_subnet.cluster_private_subneta.id, aws_subnet.cluster_private_subnetc.id]
  }
  role_arn = aws_iam_role.eks_cluster_iam_role.arn
  kubernetes_network_config {
    ip_family         = "ipv4"
    service_ipv4_cidr = "172.20.0.0/16"
  }
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-eks-cluster"
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
resource "aws_eks_addon" "vpc_cni_add_on" {
  addon_name                  = "vpc-cni"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "kube_proxy_add_on" {
  addon_name                  = "kube-proxy"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "core_dns_add_on" {
  addon_name                  = "coredns"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_node_group" "core_node_group" {
  node_group_name      = "core-nodegroup"
  ami_type             = "AL2023_x86_64_STANDARD"
  instance_types       = ["t3.large"]
  capacity_type        = "ON_DEMAND"
  cluster_name         = aws_eks_cluster.eks_cluster.name
  force_update_version = true
  node_role_arn        = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }
  subnet_ids = [aws_subnet.cluster_private_subneta.id, aws_subnet.cluster_private_subnetc.id]
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
resource "aws_vpc" "client_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "client-vpc"
  }
}
resource "aws_subnet" "client_public_subneta" {
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = local.mappings["AzMapping"]["a"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name = "client-public-subnet-a"
  }
  vpc_id = aws_vpc.client_vpc.id
}
resource "aws_route_table_association" "client_public_subneta_route_table_association" {
  route_table_id = aws_route_table.client_public_subnet_route_table.id
  subnet_id      = aws_subnet.client_public_subneta.id
}
resource "aws_subnet" "client_public_subnetc" {
  availability_zone       = "${data.aws_region.current.region}c"
  cidr_block              = local.mappings["AzMapping"]["c"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name = "client-public-subnet-c"
  }
  vpc_id = aws_vpc.client_vpc.id
}
resource "aws_route_table_association" "client_public_subnetc_route_table_association" {
  route_table_id = aws_route_table.client_public_subnet_route_table.id
  subnet_id      = aws_subnet.client_public_subnetc.id
}
resource "aws_route_table" "client_public_subnet_route_table" {
  vpc_id = aws_vpc.client_vpc.id
  tags = {
    Name = "client-public-rt"
  }
}
resource "aws_internet_gateway" "client_internet_gateway" {
  tags = {
    Name = "client-igw"
  }
}
resource "aws_internet_gateway_attachment" "client_vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.client_internet_gateway.id
  vpc_id              = aws_vpc.client_vpc.id
}
resource "aws_route" "client_public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.client_internet_gateway.id
  route_table_id         = aws_route_table.client_public_subnet_route_table.id
  depends_on             = [aws_internet_gateway_attachment.client_vpc_internet_gateway_attachment]
}
resource "aws_vpclattice_resource_gateway" "vpc_lattice_resource_gateway" {
  name                           = "eks-cluster-vpc-resource-gateway"
  vpc_id                         = aws_vpc.cluster_vpc.id
  subnet_ids                     = [aws_subnet.cluster_private_subneta.id, aws_subnet.cluster_private_subnetc.id]
  security_group_ids             = [aws_security_group.vpc_lattice_resource_gateway_security_group.id]
  ip_address_type                = "IPV4"
  resource_config_dns_resolution = "IN_VPC"
  tags = {
    Name = "eks-cluster-resource-gateway"
  }
}
resource "aws_security_group" "vpc_lattice_resource_gateway_security_group" {
  description = "VPC Lattice Resource Gateway"
  name        = "resource-gateway-sg"
  vpc_id      = aws_vpc.cluster_vpc.id
  tags = {
    Name = "resource-gateway-sg"
  }
}
resource "aws_vpc_security_group_ingress_rule" "eks_cluster_default_security_group_resource_gateway_ingress" {
  security_group_id            = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.vpc_lattice_resource_gateway_security_group.id
}
resource "aws_vpclattice_resource_configuration" "vpc_lattice_resource_configuration" {
  name                        = "eks-api-server"
  type                        = "SINGLE"
  resource_gateway_identifier = aws_vpclattice_resource_gateway.vpc_lattice_resource_gateway.id
  protocol                    = "TCP"
  port_ranges                 = ["1-65535"]
  # TODO cfn2tf: unmapped CloudFormation property 'AllowAssociationToSharableServiceNetwork' of AWS::VpcLattice::ResourceConfiguration
  # # true
  custom_domain_name = element(split("//", aws_eks_cluster.eks_cluster.endpoint), 1)
  resource_configuration_definition {
    dns_resource {
      domain_name     = element(split("//", aws_eks_cluster.eks_cluster.endpoint), 1)
      ip_address_type = "IPV4"
    }
  }
  tags = {
    Name = "eks-api-server"
  }
}
resource "aws_vpclattice_service_network" "vpc_lattice_service_network" {
  name = "eks-service-network"
}
resource "aws_vpclattice_service_network_resource_association" "vpc_lattice_service_network_resource_association" {
  resource_configuration_identifier = aws_vpclattice_resource_configuration.vpc_lattice_resource_configuration.id
  service_network_identifier        = aws_vpclattice_service_network.vpc_lattice_service_network.id
  private_dns_enabled               = true
}
resource "aws_vpc_endpoint" "vpc_lattice_service_network_endpoint" {
  vpc_endpoint_type   = "ServiceNetwork"
  vpc_id              = aws_vpc.client_vpc.id
  service_network_arn = aws_vpclattice_service_network.vpc_lattice_service_network.id
  subnet_ids          = [aws_subnet.client_public_subneta.id, aws_subnet.client_public_subnetc.id]
  security_group_ids  = [aws_security_group.vpc_lattice_service_network_endpoint_security_group.id]
}
resource "aws_security_group" "vpc_lattice_service_network_endpoint_security_group" {
  description = "VPC Lattice Service Network VPC Endpoint"
  name        = "vpc-lattice-sne-sg"
  vpc_id      = aws_vpc.client_vpc.id
  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [aws_vpc.client_vpc.cidr_block]
  }
  tags = {
    Name = "vpc-lattice-sne-sg"
  }
}
resource "aws_lambda_invocation" "vpc_lattice_service_network_endpoint_association" {
  function_name = aws_lambda_function.lambda_function.arn
  input = jsonencode({
    VpcEndpoint = aws_vpc_endpoint.vpc_lattice_service_network_endpoint.id
  })
  depends_on = [aws_vpclattice_service_network_resource_association.vpc_lattice_service_network_resource_association]
}
resource "aws_lambda_function" "lambda_function" {
  runtime          = "python3.14"
  handler          = "index.handler"
  timeout          = 900
  role             = aws_iam_role.lambda_iam_role.arn
  filename         = data.archive_file.lambda_function.output_path
  source_code_hash = data.archive_file.lambda_function.output_base64sha256
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-lambda-function"
}
resource "aws_iam_role" "lambda_iam_role" {
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
resource "aws_route53_zone" "route53_private_hosted_zone" {
  name = element(split("//", aws_eks_cluster.eks_cluster.endpoint), 1)
  vpc {
    vpc_id     = aws_vpc.client_vpc.id
    vpc_region = data.aws_region.current.region
  }
}
resource "aws_route53_record" "route53_alias_record" {
  zone_id = aws_route53_zone.route53_private_hosted_zone.zone_id
  name    = element(split("//", aws_eks_cluster.eks_cluster.endpoint), 1)
  type    = "A"
  alias {
    name                   = jsondecode(aws_lambda_invocation.vpc_lattice_service_network_endpoint_association.result)["DnsName"]
    zone_id                = jsondecode(aws_lambda_invocation.vpc_lattice_service_network_endpoint_association.result)["HostedZoneId"]
    evaluate_target_health = false
  }
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT15M"
# #   }
# # }
resource "aws_instance" "vs_code_ec2" {
  ami                  = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type        = "t3.medium"
  key_name             = aws_key_pair.key_pair.key_name
  iam_instance_profile = aws_iam_instance_profile.vs_code_ec2_instance_profile.name
  tags = {
    Name = "vscode"
  }
  user_data                   = <<EOT
#!/bin/bash
dnf update -yq
dnf install -yq git bind-utils
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

echo '# FQDN resolves to Private IPs without VPC Lattice Service Network / VPC Peering Connection / Transit Gateway
dig ${element(split("//", aws_eks_cluster.eks_cluster.endpoint), 1)}

# HTTP 401 Unauthorized is expected
curl https://${element(split("//", aws_eks_cluster.eks_cluster.endpoint), 1)} -vk

aws eks update-kubeconfig --name ${aws_eks_cluster.eks_cluster.name} --region ${data.aws_region.current.region}
' > /home/ec2-user/README.md

EOF

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource VsCodeEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.client_public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.vs_code_ec2_security_group.id]
  depends_on                  = [aws_eks_node_group.core_node_group]
}
resource "aws_security_group" "vs_code_ec2_security_group" {
  description = "Security Group"
  name        = "vscode-sg"
  vpc_id      = aws_vpc.client_vpc.id
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
    Name = "vscode-sg"
  }
}
resource "aws_iam_role" "vs_code_ec2_iam_role" {
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
resource "aws_iam_instance_profile" "vs_code_ec2_instance_profile" {
  role = jsonencode([aws_iam_role.vs_code_ec2_iam_role.name])
}
resource "aws_eks_access_entry" "vs_code_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  type          = "STANDARD"
  principal_arn = aws_iam_role.vs_code_ec2_iam_role.arn
}
# --- Outputs ---
# CloudFormation output: VsCode
output "vs_code" {
  value       = "http://${aws_instance.vs_code_ec2.public_ip}:8000"
  description = "Public IP Address of the VS Code"
}
# CloudFormation output: EksClusterApiServerEndpoint
output "eks_cluster_api_server_endpoint" {
  value       = aws_eks_cluster.eks_cluster.endpoint
  description = "EKS Cluster API Server - Private Endpoint (ClusterVpc)"
}
