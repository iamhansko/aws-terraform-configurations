# Generated from 000_deprecated/eks/internal/computing/managed_node_group/internal/nlb_service.yaml by tools/cfn2tf.
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
  default     = "nlb-service"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "kubernetes_version" {
  type        = string
  default     = "1.31"
  description = "EKS Cluster Kubernetes Version (1.XX)"
  validation {
    condition     = contains(["1.24", "1.25", "1.26", "1.27", "1.28", "1.29", "1.30", "1.31", "1.32"], var.kubernetes_version)
    error_message = "KubernetesVersion must be one of: 1.24, 1.25, 1.26, 1.27, 1.28, 1.29, 1.30, 1.31, 1.32"
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
    ResourceMap = {
      Vpc = {
        Name      = "eks-vpc"
        CidrBlock = "192.168.0.0/16"
      }
      PublicSubnet = {
        Name = "eks-public"
      }
      PrivateSubnet = {
        Name = "eks-private"
      }
      InternetGateway = {
        Name = "eks-igw"
      }
      NatGateway = {
        Name = "eks-natgw"
      }
      BastionEc2 = {
        Name         = "eks-bastion"
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
resource "aws_iam_role_policy" "bastion_ec2_iam_role" {
  name = "BastionEc2IamPolicy"
  role = aws_iam_role.bastion_ec2_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:*", "cloudformation:*", "iam:*"]
      Resource = "*"
    }]
  })
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
resource "aws_eks_access_policy_association" "eks_cluster_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
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
resource "aws_vpc" "vpc" {
  enable_dns_hostnames = true
  cidr_block           = local.mappings["ResourceMap"]["Vpc"]["CidrBlock"]
  tags = {
    Name = local.mappings["ResourceMap"]["Vpc"]["Name"]
  }
}
resource "aws_subnet" "private_subnet_a" {
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = element([for __i in range(16) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 0)
  tags = {
    Name                              = join("-", [local.mappings["ResourceMap"]["PrivateSubnet"]["Name"], "a"])
    "kubernetes.io/role/internal-elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_subnet" "private_subnet_b" {
  availability_zone = "${data.aws_region.current.region}b"
  cidr_block        = element([for __i in range(16) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 1)
  tags = {
    Name                              = join("-", [local.mappings["ResourceMap"]["PrivateSubnet"]["Name"], "b"])
    "kubernetes.io/role/internal-elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_subnet" "private_subnet_c" {
  availability_zone = "${data.aws_region.current.region}c"
  cidr_block        = element([for __i in range(16) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 2)
  tags = {
    Name                              = join("-", [local.mappings["ResourceMap"]["PrivateSubnet"]["Name"], "c"])
    "kubernetes.io/role/internal-elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_subnet" "public_subnet_a" {
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = element([for __i in range(16) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 3)
  map_public_ip_on_launch = true
  tags = {
    Name                     = join("-", [local.mappings["ResourceMap"]["PublicSubnet"]["Name"], "a"])
    "kubernetes.io/role/elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_subnet" "public_subnet_b" {
  availability_zone       = "${data.aws_region.current.region}b"
  cidr_block              = element([for __i in range(16) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 4)
  map_public_ip_on_launch = true
  tags = {
    Name                     = join("-", [local.mappings["ResourceMap"]["PublicSubnet"]["Name"], "b"])
    "kubernetes.io/role/elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_subnet" "public_subnet_c" {
  availability_zone       = "${data.aws_region.current.region}c"
  cidr_block              = element([for __i in range(16) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 5)
  map_public_ip_on_launch = true
  tags = {
    Name                     = join("-", [local.mappings["ResourceMap"]["PublicSubnet"]["Name"], "c"])
    "kubernetes.io/role/elb" = 1
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
resource "aws_eip" "nat_gateway_c_elastic_ip" {}
resource "aws_nat_gateway" "nat_gateway_c" {
  allocation_id = aws_eip.nat_gateway_c_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_c.id
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["NatGateway"]["Name"], "c"])
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
resource "aws_route_table_association" "public_subnet_c_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_c.id
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
resource "aws_route_table" "private_subnet_c_route_table" {
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PrivateSubnet"]["Name"], "c", "rt"])
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "private_subnet_c_route_table_association" {
  route_table_id = aws_route_table.private_subnet_c_route_table.id
  subnet_id      = aws_subnet.private_subnet_c.id
}
resource "aws_route" "private_subnet_c_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_c.id
  route_table_id         = aws_route_table.private_subnet_c_route_table.id
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT20M"
# #   }
# # }
resource "aws_instance" "bastion_ec2" {
  ami           = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type = local.mappings["ResourceMap"]["BastionEc2"]["InstanceType"]
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = local.mappings["ResourceMap"]["BastionEc2"]["Name"]
  }
  iam_instance_profile        = aws_iam_instance_profile.bastion_ec2_instance_profile.name
  user_data                   = <<EOT
#!/bin/bash
dnf update -y
dnf install -y git
dnf groupinstall -y "Development Tools"
dnf install -y python3.12
dnf install -y python3-pip
ln -s /usr/bin/python3.12 /usr/bin/python

wget https://github.com/coder/code-server/releases/download/v4.93.1/code-server-4.93.1-linux-amd64.tar.gz
tar -xzf code-server-4.93.1-linux-amd64.tar.gz
mv code-server-4.93.1-linux-amd64 /usr/local/lib/code-server
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
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.30.0/2024-05-12/bin/linux/amd64/kubectl
chmod +x kubectl
mv kubectl /home/ec2-user/bin/kubectl
export PATH=/home/ec2-user/bin:$PATH
echo "export PATH=/home/ec2-user/bin:$PATH" >> ~/.bashrc
echo "alias k=kubectl" >>~/.bashrc
echo "complete -o default -F __start_kubectl k" >>~/.bashrc
echo "source <(kubectl completion bash)" >>~/.bashrc
exec bash
aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${aws_eks_cluster.eks_cluster.name}

curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
aws configure set region ${data.aws_region.current.region}

curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > /home/ec2-user/get_helm.sh
chmod 700 /home/ec2-user/get_helm.sh
/home/ec2-user/get_helm.sh

sleep 5
eksctl create iamserviceaccount \
--cluster=${aws_eks_cluster.eks_cluster.name} \
--namespace=kube-system \
--name=aws-load-balancer-controller \
--role-name AmazonEKSLoadBalancerControllerRole \
--attach-policy-arn=${aws_iam_policy.aws_load_balancer_controller_iam_policy.arn} \
--approve --region ${data.aws_region.current.region}
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system \
--set clusterName=${aws_eks_cluster.eks_cluster.name} \
--set serviceAccount.create=false \
--set serviceAccount.name=aws-load-balancer-controller \
--set region=${data.aws_region.current.region} \
--set vpcId=${aws_vpc.vpc.id}
kubectl rollout status -n kube-system deploy aws-load-balancer-controller
sleep 5

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

git clone https://codeberg.org/hjacobs/kube-ops-view.git
cd kube-ops-view/
kubectl apply -k deploy
kubectl patch svc kube-ops-view -p '{"metadata": {"annotations": {"service.beta.kubernetes.io/aws-load-balancer-nlb-target-type": "ip", "service.beta.kubernetes.io/aws-load-balancer-scheme":"internal", "service.beta.kubernetes.io/aws-load-balancer-manage-backend-security-group-rules":"true", "service.beta.kubernetes.io/aws-load-balancer-security-groups":"${aws_security_group.nlb_service_security_group.id}"}}, "spec": {"type": "LoadBalancer", "loadBalancerClass": "service.k8s.aws/nlb"}}'

EOF

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource BastionEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subnet_a.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_ec2_security_group.id]
  depends_on                  = [aws_eks_cluster.eks_cluster, aws_iam_openid_connect_provider.eks_oidc_provider]
}
resource "aws_security_group" "bastion_ec2_security_group" {
  description = "Security Group for Bastion EC2 SSH Connection"
  name        = "bastion-sg"
  vpc_id      = aws_vpc.vpc.id
  tags = {
    Name = "bastion-sg"
  }
}
resource "aws_iam_role" "bastion_ec2_iam_role" {
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
resource "aws_iam_instance_profile" "bastion_ec2_instance_profile" {
  role = jsonencode([aws_iam_role.bastion_ec2_iam_role.name])
}
resource "aws_iam_policy" "aws_load_balancer_controller_iam_policy" {
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
  name = "AWSLoadBalancerControllerIAMPolicy"
}
resource "aws_security_group" "nlb_service_security_group" {
  description = "Security Group for NLB"
  name        = "nlb-sg"
  vpc_id      = aws_vpc.vpc.id
  tags = {
    Name = "nlb-sg"
  }
}
resource "aws_eks_cluster" "eks_cluster" {
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = false
    security_group_ids      = [aws_security_group.kubectl_security_group.id]
    subnet_ids              = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id, aws_subnet.public_subnet_c.id, aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id, aws_subnet.private_subnet_c.id]
  }
  role_arn                  = aws_iam_role.eks_cluster_iam_role.arn
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-eks-cluster"
}
resource "aws_security_group" "kubectl_security_group" {
  description = "Security Group for EKS Cluster Connection"
  name        = "kubectl-sg"
  ingress {
    protocol        = -1
    security_groups = [aws_security_group.bastion_ec2_security_group.id]
    from_port       = 0
    to_port         = 0
  }
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "kubectl-sg"
  }
}
resource "aws_eks_node_group" "managed_node_group" {
  node_group_name      = "app-mng"
  ami_type             = "AL2023_x86_64_STANDARD"
  instance_types       = ["t3.medium"]
  capacity_type        = "ON_DEMAND"
  cluster_name         = aws_eks_cluster.eks_cluster.name
  force_update_version = true
  labels = {
    "mng/dedicated" = "app"
  }
  node_role_arn = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }
  subnet_ids = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id, aws_subnet.private_subnet_c.id]
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
resource "aws_eks_access_entry" "eks_cluster_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  type          = "STANDARD"
}
resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url            = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
