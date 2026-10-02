# Generated from 060_eks_node_termination_handler/nth_queue_processor.yaml by tools/cfn2tf.
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
  default     = "nth-queue-processor"
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
  default     = "1.33"
  description = "EKS Cluster Kubernetes Version (1.XX)"
  validation {
    condition     = contains(["1.31", "1.32", "1.33"], var.kubernetes_version)
    error_message = "KubernetesVersion must be one of: 1.31, 1.32, 1.33"
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
resource "aws_iam_role_policy_attachment" "vs_code_ec2_iam_role" {
  role       = aws_iam_role.vs_code_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_iam_role_policy_attachment" "eks_cluster_iam_role" {
  role       = aws_iam_role.eks_cluster_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
resource "aws_eks_access_policy_association" "vs_code_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.vs_code_ec2_iam_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
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
data "archive_file" "custom_resource_lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/custom_resource_lambda_function/index.py"
  output_path = "${path.module}/build/custom_resource_lambda_function.zip"
}
resource "aws_iam_role_policy" "custom_resource_lambda_function_iam_role" {
  name = "CustomResourcePolicy"
  role = aws_iam_role.custom_resource_lambda_function_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:DescribeNodegroup", "autoscaling:DescribeAutoScalingGroups"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "custom_resource_lambda_function_iam_role" {
  role       = aws_iam_role.custom_resource_lambda_function_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
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
resource "aws_iam_role_policy" "fis_iam_role" {
  name = "aws-fis-policy"
  role = aws_iam_role.fis_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["fis:*"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "fis_iam_role" {
  role       = aws_iam_role.fis_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEC2Access"
}
resource "aws_iam_role_policy" "node_termination_handler_role" {
  name = "NodeTerminationHandlerPolicy"
  role = aws_iam_role.node_termination_handler_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["autoscaling:CompleteLifecycleAction", "autoscaling:DescribeAutoScalingInstances", "autoscaling:DescribeTags", "ec2:DescribeInstances", "sqs:DeleteMessage", "sqs:ReceiveMessage"]
      Resource = "*"
    }]
  })
}
resource "aws_cloudwatch_event_target" "asg_term_rule" {
  rule      = aws_cloudwatch_event_rule.asg_term_rule.name
  arn       = aws_sqs_queue.queue.arn
  target_id = 1
}
resource "aws_cloudwatch_event_target" "scheduled_change_rule" {
  rule      = aws_cloudwatch_event_rule.scheduled_change_rule.name
  arn       = aws_sqs_queue.queue.arn
  target_id = 1
}
resource "aws_cloudwatch_event_target" "spot_term_rule" {
  rule      = aws_cloudwatch_event_rule.spot_term_rule.name
  arn       = aws_sqs_queue.queue.arn
  target_id = 1
}
resource "aws_cloudwatch_event_target" "rebalance_rule" {
  rule      = aws_cloudwatch_event_rule.rebalance_rule.name
  arn       = aws_sqs_queue.queue.arn
  target_id = 1
}
resource "aws_cloudwatch_event_target" "instance_state_change_rule" {
  rule      = aws_cloudwatch_event_rule.instance_state_change_rule.name
  arn       = aws_sqs_queue.queue.arn
  target_id = 1
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
resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = "igw"
  }
}
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
resource "aws_route_table" "public_subnet_route_table" {
  tags = {
    Name = "public-rt"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route" "public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id
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
resource "aws_subnet" "public_subnetb" {
  availability_zone       = "${data.aws_region.current.region}b"
  cidr_block              = local.mappings["AzMapping"]["b"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-b"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subnetb_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnetb.id
}
resource "aws_subnet" "private_subneta" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = local.mappings["AzMapping"]["a"]["PrivateSubnetCidr"]
  availability_zone = "${data.aws_region.current.region}a"
  tags = {
    Name = "private-subnet-a"
  }
}
resource "aws_route_table" "private_subneta_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "private-rt-a"
  }
}
resource "aws_eip" "natgatewaya_elastic_ip" {}
resource "aws_nat_gateway" "nat_gatewaya" {
  allocation_id = aws_eip.natgatewaya_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subneta.id
  tags = {
    Name = "natgw-a"
  }
}
resource "aws_route_table_association" "private_subneta_route_table_association" {
  route_table_id = aws_route_table.private_subneta_route_table.id
  subnet_id      = aws_subnet.private_subneta.id
}
resource "aws_route" "private_subneta_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gatewaya.id
  route_table_id         = aws_route_table.private_subneta_route_table.id
}
resource "aws_subnet" "private_subnetb" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = local.mappings["AzMapping"]["b"]["PrivateSubnetCidr"]
  availability_zone = "${data.aws_region.current.region}b"
  tags = {
    Name = "private-subnet-b"
  }
}
resource "aws_route_table" "private_subnetb_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "private-rt-b"
  }
}
resource "aws_eip" "natgatewayb_elastic_ip" {}
resource "aws_nat_gateway" "nat_gatewayb" {
  allocation_id = aws_eip.natgatewayb_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnetb.id
  tags = {
    Name = "natgw-b"
  }
}
resource "aws_route_table_association" "private_subnetb_route_table_association" {
  route_table_id = aws_route_table.private_subnetb_route_table.id
  subnet_id      = aws_subnet.private_subnetb.id
}
resource "aws_route" "private_subnetb_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gatewayb.id
  route_table_id         = aws_route_table.private_subnetb_route_table.id
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT7M"
# #   }
# # }
resource "aws_instance" "vs_code_ec2" {
  ami           = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type = "t3.medium"
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = "vscode"
  }
  iam_instance_profile        = aws_iam_instance_profile.vs_code_ec2_instance_profile.name
  user_data                   = <<EOT
#!/bin/bash
dnf update -yq
dnf install -yq git
dnf groupinstall -yq "Development Tools"

export VSC_VERSION="4.102.3"
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
aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${aws_eks_cluster.eks_cluster.name}

curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > /home/ec2-user/get_helm.sh
chmod 700 /home/ec2-user/get_helm.sh
/home/ec2-user/get_helm.sh

helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system \
--set clusterName=${aws_eks_cluster.eks_cluster.name} \
--set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${aws_iam_role.aws_load_balancer_controller_role.arn}" \
--set serviceAccount.name=aws-load-balancer-controller \
--set region=${data.aws_region.current.region} \
--set vpcId=${aws_vpc.vpc.id} \
--wait
sleep 60
EOF

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource VsCodeEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id, aws_security_group.vs_code_ec2_security_group.id]
  depends_on                  = [aws_eks_node_group.on_demand_node_group, aws_eks_node_group.spot_node_group]
}
resource "aws_security_group" "vs_code_ec2_security_group" {
  description = "Security Group"
  name        = "vscode-sg"
  vpc_id      = aws_vpc.vpc.id
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
resource "aws_eks_cluster" "eks_cluster" {
  version = var.kubernetes_version
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    subnet_ids              = [aws_subnet.public_subneta.id, aws_subnet.public_subnetb.id, aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
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
resource "aws_eks_access_entry" "vs_code_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.vs_code_ec2_iam_role.arn
  type          = "STANDARD"
}
resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url            = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_eks_addon" "vpc_cni_add_on" {
  addon_name   = "vpc-cni"
  cluster_name = aws_eks_cluster.eks_cluster.name
}
resource "aws_eks_addon" "kube_proxy_add_on" {
  addon_name   = "kube-proxy"
  cluster_name = aws_eks_cluster.eks_cluster.name
}
resource "aws_eks_addon" "core_dns_add_on" {
  addon_name   = "coredns"
  cluster_name = aws_eks_cluster.eks_cluster.name
}
resource "aws_eks_node_group" "on_demand_node_group" {
  node_group_name      = "ondemand-nodegroup"
  ami_type             = "AL2023_x86_64_STANDARD"
  instance_types       = ["t3.medium"]
  capacity_type        = "ON_DEMAND"
  cluster_name         = aws_eks_cluster.eks_cluster.name
  force_update_version = true
  node_role_arn        = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }
  subnet_ids = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  launch_template {
    id      = aws_launch_template.on_demand_launch_template.id
    version = aws_launch_template.on_demand_launch_template.latest_version
  }
  tags = {
    mng = "ondemand"
  }
}
resource "aws_launch_template" "on_demand_launch_template" {
  name                   = "ondemand-nodegroup-launchtemplate"
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id]
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name                                   = "ondemand"
      "aws-node-termination-handler/managed" = "1"
    }
  }
}
resource "aws_eks_node_group" "spot_node_group" {
  node_group_name      = "spot-nodegroup"
  ami_type             = "AL2023_x86_64_STANDARD"
  instance_types       = ["t3.medium"]
  capacity_type        = "SPOT"
  cluster_name         = aws_eks_cluster.eks_cluster.name
  force_update_version = true
  node_role_arn        = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }
  subnet_ids = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  launch_template {
    id      = aws_launch_template.spot_launch_template.id
    version = aws_launch_template.spot_launch_template.latest_version
  }
  tags = {
    mng = "spot"
  }
}
resource "aws_launch_template" "spot_launch_template" {
  name                   = "spot-nodegroup-launchtemplate"
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id]
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name                                   = "spot"
      "aws-node-termination-handler/managed" = "1"
    }
  }
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
resource "aws_lambda_invocation" "get_eks_cluster_on_demand_asg" {
  function_name = aws_lambda_function.custom_resource_lambda_function.arn
  input = jsonencode({
    ClusterName   = aws_eks_cluster.eks_cluster.name
    NodegroupName = aws_eks_node_group.on_demand_node_group.node_group_name
  })
}
resource "aws_lambda_invocation" "get_eks_cluster_spot_asg" {
  function_name = aws_lambda_function.custom_resource_lambda_function.arn
  input = jsonencode({
    ClusterName   = aws_eks_cluster.eks_cluster.name
    NodegroupName = aws_eks_node_group.spot_node_group.node_group_name
  })
}
resource "aws_lambda_function" "custom_resource_lambda_function" {
  runtime          = "python3.13"
  handler          = "index.lambda_handler"
  role             = aws_iam_role.custom_resource_lambda_function_iam_role.arn
  filename         = data.archive_file.custom_resource_lambda_function.output_path
  source_code_hash = data.archive_file.custom_resource_lambda_function.output_base64sha256
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-custom-resource-lambda-function"
}
resource "aws_iam_role" "custom_resource_lambda_function_iam_role" {
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
resource "aws_iam_role" "aws_load_balancer_controller_role" {
  assume_role_policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Principal": {
              "Federated": "${aws_iam_openid_connect_provider.eks_oidc_provider.arn}"
          },
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Condition": {
              "StringEquals": {
                  "${element(split("//", aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer), 1)}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller",
                  "${element(split("//", aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer), 1)}:aud": "sts.amazonaws.com"
              }
          }
      }
  ]
}
EOT
}
resource "aws_ssm_association" "ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 600
  targets {
    key    = "InstanceIds"
    values = [aws_instance.vs_code_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << 'SSMEOF'\nexport HOME=/home/ec2-user && cd $HOME\naws configure set region ${data.aws_region.current.region}\n\necho $'#!/bin/bash\nhelm upgrade --install aws-node-termination-handler oci://public.ecr.aws/aws-ec2/helm/aws-node-termination-handler -n kube-system \\\n--set replicas=3 \\\n--set enableSqsTerminationDraining=true \\\n--set queueURL=${aws_sqs_queue.queue.url} \\\n--set serviceAccount.annotations.\"eks\\.amazonaws\\.com/role-arn\"=${aws_iam_role.node_termination_handler_role.arn} \\\n--wait' > install_nth.sh\n# --set checkTagBeforeDraining=true \\\nchmod +x install_nth.sh\n./install_nth.sh\n\nmkdir -p /home/ec2-user/manifests\necho 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  labels:\n    app: nginx\n  name: nginx\nspec:\n  replicas: 12\n  selector:\n    matchLabels:\n      app: nginx\n  template:\n    metadata:\n      creationTimestamp: null\n      labels:\n        app: nginx\n    spec:\n      containers:\n      - image: nginx\n        name: nginx' > /home/ec2-user/manifests/nginx.yaml\nkubectl apply -f /home/ec2-user/manifests/nginx.yaml\n\nwget -O eks-node-viewer https://github.com/awslabs/eks-node-viewer/releases/download/v0.7.4/eks-node-viewer_Linux_x86_64\nchmod +x eks-node-viewer\nsudo mv -v eks-node-viewer /usr/local/bin\n\nwget https://github.com/aws/amazon-ec2-spot-interrupter/releases/download/v0.0.10/ec2-spot-interrupter_0.0.10_Linux_amd64.tar.gz\ntar -xvzf ec2-spot-interrupter_0.0.10_Linux_amd64.tar.gz\nchmod +x ec2-spot-interrupter\nsudo mv -v ec2-spot-interrupter /usr/local/bin\n\nSSMEOF\n"])
  }
  depends_on = [aws_instance.vs_code_ec2]
}
resource "aws_iam_role" "fis_iam_role" {
  name = "aws-fis-nth-queue-processor"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["fis.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_iam_role" "node_termination_handler_role" {
  assume_role_policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Principal": {
              "Federated": "${aws_iam_openid_connect_provider.eks_oidc_provider.arn}"
          },
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Condition": {
              "StringEquals": {
                  "${element(split("//", aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer), 1)}:sub": "system:serviceaccount:kube-system:aws-node-termination-handler",
                  "${element(split("//", aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer), 1)}:aud": "sts.amazonaws.com"
              }
          }
      }
  ]
}
EOT
}
resource "aws_sqs_queue" "queue" {
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
}
resource "aws_sqs_queue_policy" "queue_policy" {
  queue_url = jsonencode([aws_sqs_queue.queue.id])
  policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["events.amazonaws.com", "sqs.amazonaws.com"]
      }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.queue.arn
    }]
  })
}
resource "aws_cloudwatch_event_rule" "asg_term_rule" {
  event_pattern = jsonencode({
    source        = ["aws.autoscaling"]
    "detail-type" = ["EC2 Instance-terminate Lifecycle Action"]
  })
}
resource "aws_cloudwatch_event_rule" "scheduled_change_rule" {
  event_pattern = jsonencode({
    source        = ["aws.health"]
    "detail-type" = ["AWS Health Event"]
    detail = {
      service           = ["EC2"]
      eventTypeCategory = ["scheduledChange"]
    }
  })
}
resource "aws_cloudwatch_event_rule" "spot_term_rule" {
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Spot Instance Interruption Warning"]
  })
}
resource "aws_cloudwatch_event_rule" "rebalance_rule" {
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance Rebalance Recommendation"]
  })
}
resource "aws_cloudwatch_event_rule" "instance_state_change_rule" {
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
  })
}
resource "aws_autoscaling_lifecycle_hook" "on_demand_asg_instance_terminating_lifecycle_hook" {
  autoscaling_group_name = jsondecode(aws_lambda_invocation.get_eks_cluster_on_demand_asg.result)["AutoScalingGroupName"]
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
  default_result         = "CONTINUE"
  heartbeat_timeout      = 300
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-on-demand-asg-instance-terminating-lifecycle-hook"
}
resource "aws_autoscaling_lifecycle_hook" "on_demand_asg_instance_launching_lifecycle_hook" {
  autoscaling_group_name = jsondecode(aws_lambda_invocation.get_eks_cluster_on_demand_asg.result)["AutoScalingGroupName"]
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"
  default_result         = "ABANDON"
  heartbeat_timeout      = 300
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-on-demand-asg-instance-launching-lifecycle-hook"
}
resource "aws_autoscaling_lifecycle_hook" "spot_asg_instance_terminating_lifecycle_hook" {
  autoscaling_group_name = jsondecode(aws_lambda_invocation.get_eks_cluster_spot_asg.result)["AutoScalingGroupName"]
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
  default_result         = "CONTINUE"
  heartbeat_timeout      = 300
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-spot-asg-instance-terminating-lifecycle-hook"
}
resource "aws_autoscaling_lifecycle_hook" "spot_asg_instance_launching_lifecycle_hook" {
  autoscaling_group_name = jsondecode(aws_lambda_invocation.get_eks_cluster_spot_asg.result)["AutoScalingGroupName"]
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"
  default_result         = "ABANDON"
  heartbeat_timeout      = 300
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-spot-asg-instance-launching-lifecycle-hook"
}
# --- Outputs ---
# CloudFormation output: VsCode
output "vs_code" {
  value       = "http://${aws_instance.vs_code_ec2.public_ip}:8000"
  description = "Public IP Address of the VS Code"
}
# CloudFormation output: Commands
output "commands" {
  value       = "ec2-spot-interrupter -d 13m -i SPOT_INSTANCE_ID -r ${data.aws_region.current.region}"
  description = "https://github.com/aws/amazon-ec2-spot-interrupter"
}
