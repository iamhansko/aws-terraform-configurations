# Generated from 049_eks_argocd_vault/cluster.yaml by tools/cfn2tf.
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
  default     = "cluster"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "git_hub_user" {
  type = string
}
variable "git_hub_repo" {
  type    = string
  default = "sample-eks-argocd"
}
variable "git_hub_token" {
  type = string
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
resource "aws_iam_role_policy_attachment" "ebs_csi_driver_addon_iam_role" {
  role       = aws_iam_role.ebs_csi_driver_addon_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
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

kubectl -n kube-system rollout status deployment ebs-csi-controller
kubectl -n kube-system rollout status daemonset ebs-csi-node
sleep 10
mkdir -p /home/ec2-user/manifests
echo 'apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
parameters:
  type: gp3
provisioner: ebs.csi.aws.com
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer' > manifests/gp3_storageclass.yaml
kubectl apply -f manifests/gp3_storageclass.yaml

EOF

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource VsCodeEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id, aws_security_group.vs_code_ec2_security_group.id]
  depends_on                  = [aws_eks_node_group.core_node_group]
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
resource "aws_eks_node_group" "core_node_group" {
  node_group_name      = "core-nodegroup"
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
resource "aws_lb" "vault" {
  name               = "vault"
  load_balancer_type = "application"
  security_groups    = [aws_vpc.vpc.default_security_group_id]
  subnets            = [aws_subnet.public_subneta.id, aws_subnet.public_subnetb.id]
  tags = {
    "elbv2.k8s.aws/cluster"    = aws_eks_cluster.eks_cluster.name
    "ingress.k8s.aws/resource" = "LoadBalancer"
    "ingress.k8s.aws/stack"    = "vault/vault"
  }
  internal = false
}
resource "aws_security_group" "alb_security_group" {
  description = "Security Group"
  name        = "alb-sg"
  dynamic "ingress" {
    for_each = local.cond_security_group_inbound_from_anywhere ? [1] : []
    content {
      protocol    = "tcp"
      from_port   = 80
      to_port     = 80
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "alb-sg"
  }
}
resource "aws_lb" "argocd" {
  name               = "argocd"
  load_balancer_type = "network"
  security_groups    = [aws_vpc.vpc.default_security_group_id]
  subnets            = [aws_subnet.public_subneta.id, aws_subnet.public_subnetb.id]
  tags = {
    "elbv2.k8s.aws/cluster"    = aws_eks_cluster.eks_cluster.name
    "service.k8s.aws/resource" = "LoadBalancer"
    "service.k8s.aws/stack"    = "argocd/argocd-server"
  }
  internal = false
}
resource "aws_security_group" "nlb_security_group" {
  description = "Security Group"
  name        = "nlb-sg"
  dynamic "ingress" {
    for_each = local.cond_security_group_inbound_from_anywhere ? [1] : []
    content {
      protocol    = "tcp"
      from_port   = 80
      to_port     = 80
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "nlb-sg"
  }
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
resource "aws_eks_addon" "ebs_csi_driver_addon" {
  addon_name               = "aws-ebs-csi-driver"
  cluster_name             = aws_eks_cluster.eks_cluster.name
  service_account_role_arn = aws_iam_role.ebs_csi_driver_addon_iam_role.arn
}
resource "aws_iam_role" "ebs_csi_driver_addon_iam_role" {
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
                  "${element(split("//", aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer), 1)}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa",
                  "${element(split("//", aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer), 1)}:aud": "sts.amazonaws.com"
              }
          }
      }
  ]
}
EOT
}
# === GitHubRepository (AWS::CodeStar::GitHubRepository) NOT CONVERTED ===
# Legacy CodeStar resource; the AWS provider has no equivalent. Use the GitHub provider.
# Original CloudFormation definition:
# # {
# #   "Type": "AWS::CodeStar::GitHubRepository",
# #   "DependsOn": [
# #     "GitHubSsmAssociation"
# #   ],
# #   "Properties": {
# #     "EnableIssues": true,
# #     "IsPrivate": false,
# #     "RepositoryAccessToken": {
# #       "Ref": "GitHubToken"
# #     },
# #     "RepositoryName": {
# #       "Ref": "GitHubRepo"
# #     },
# #     "RepositoryOwner": {
# #       "Ref": "GitHubUser"
# #     },
# #     "Code": {
# #       "S3": {
# #         "Bucket": {
# #           "Ref": "GitHubS3Bucket"
# #         },
# #         "Key": "src.zip"
# #       }
# #     }
# #   }
# # }
resource "aws_codestarconnections_connection" "git_hub_connection" {
  name          = "github-connection"
  provider_type = "GitHub"
}
resource "aws_codebuild_source_credential" "git_hub_credential" {
  auth_type   = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token       = var.git_hub_token
  user_name   = var.git_hub_user
}
resource "aws_s3_bucket" "git_hub_s3_bucket" {
  bucket = "github-source-bucket-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
}
resource "aws_ssm_association" "git_hub_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 900
  targets {
    key    = "InstanceIds"
    values = [aws_instance.vs_code_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << EOF\nmkdir -p /home/ec2-user/${var.git_hub_repo}/.github/workflows\nmkdir -p /home/ec2-user/${var.git_hub_repo}/manifest\ncd /home/ec2-user/${var.git_hub_repo}\n\necho 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: nginx-deploy\n  labels:\n    app: nginx\nspec:\n  replicas: 3\n  selector:\n    matchLabels:\n      app: nginx\n  template:\n    metadata:\n      labels:\n        app: nginx\n    spec:\n      containers:\n      - name: nginx\n        image: nginx:latest\n        env:\n        - name: ADMIN_USER\n          value: <path:kv/data/admin#user>\n        - name: ADMIN_PASSWORD\n          value: <path:kv/data/admin#password>\n' > ./manifest/deployment.yaml\n\necho 'apiVersion: v1\nkind: Service\nmetadata:\n  name: nginx-service\nspec:\n  selector:\n    app: nginx\n  ports:\n    - protocol: TCP\n      port: 80\n      targetPort: 80' > ./manifest/service.yaml\n\necho 'apiVersion: networking.k8s.io/v1\nkind: Ingress\nmetadata:\n  name: nginx-ingress\n  annotations:\n    alb.ingress.kubernetes.io/load-balancer-name: sample\n    alb.ingress.kubernetes.io/scheme: internet-facing\n    alb.ingress.kubernetes.io/target-type: ip\nspec:\n  ingressClassName: alb\n  rules:\n  - http:\n      paths:\n      - path: /\n        pathType: Prefix\n        backend:\n          service:\n            name: nginx-service\n            port:\n              number: 80' > ./manifest/ingress.yaml\n\nzip -r src.zip . \"./*\"\naws s3 cp src.zip s3://${aws_s3_bucket.git_hub_s3_bucket.id}\n\nEOF\n"])
  }
  depends_on = [aws_instance.vs_code_ec2]
}
resource "aws_ssm_association" "ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 1200
  targets {
    key    = "InstanceIds"
    values = [aws_instance.vs_code_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << 'SSMEOF'\nexport HOME=/home/ec2-user && cd $HOME\n\nhelm repo add hashicorp https://helm.releases.hashicorp.com\nhelm repo update hashicorp\nhelm install vault hashicorp/vault -n vault --create-namespace \\\n--set ingress.enabled=\"true\" \\\n--set ingress.ingressClassName=\"alb\" \\\n--set ingress.annotations.\"alb\\.ingress\\.kubernetes\\.io/scheme\"=internet-facing \\\n--set ingress.annotations.\"alb\\.ingress\\.kubernetes\\.io/target-type\"=ip \\\n--set ingress.annotations.\"alb\\.ingress\\.kubernetes\\.io/security-groups\"=\"${aws_security_group.alb_security_group.id}\\, ${aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id}\" \\\n--wait\nsleep 10\nkubectl -n vault exec vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json > vault_token.json\nexport VAULT_INITIAL_ROOT_TOKEN=$(cat vault_token.json | jq -r \".root_token\")\necho $'apiVersion: v1\nkind: Secret\nmetadata:\n  name: vault\n  namespace: argocd\ntype: Opaque\nstringData:\n  VAULT_ADDR: http://vault.vault:8200\n  VAULT_TOKEN: $VAULT_INITIAL_ROOT_TOKEN\n  AVP_AUTH_TYPE: token\n  AVP_TYPE: vault\n---\napiVersion: rbac.authorization.k8s.io/v1\nkind: Role\nmetadata:\n  name: argocd-repo-server\n  namespace: argocd\nrules:\n- apiGroups: [\"\"]\n  resources: [\"secrets\"]\n  resourceNames: [\"vault\"]\n  verbs: [\"get\"]\n---\napiVersion: rbac.authorization.k8s.io/v1\nkind: RoleBinding\nmetadata:\n  name: argocd-repo-server\n  namespace: argocd\nroleRef:\n  apiGroup: rbac.authorization.k8s.io\n  kind: Role\n  name: argocd-repo-server\nsubjects:\n- kind: ServiceAccount\n  name: argocd-repo-server' > manifests/vault.yaml\nkubectl apply -f manifests/vault.yaml\nkubectl -n vault exec vault-0 -- vault login $VAULT_INITIAL_ROOT_TOKEN\n# kubectl -n vault exec vault-0 -- vault secrets enable kv-v2\n# kubectl -n vault exec vault-0 -- vault kv put admin name=\"hyunsu\" password=\"hyunsu1234\"\n\ncurl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64\nsudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd\nrm argocd-linux-amd64\n\nkubectl create namespace argocd\nkubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml\nsleep 10\nkubectl -n argocd annotate service argocd-server service.beta.kubernetes.io/aws-load-balancer-scheme=\"internet-facing\"\nkubectl -n argocd annotate service argocd-server service.beta.kubernetes.io/aws-load-balancer-nlb-target-type=\"ip\"\nkubectl -n argocd annotate service argocd-server service.beta.kubernetes.io/aws-load-balancer-security-groups=\"${aws_security_group.nlb_security_group.id}\\, ${aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id}\"\nkubectl -n argocd patch service argocd-server -p '{\"spec\": {\"type\": \"LoadBalancer\"}}'\nsleep 60\n\necho 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: cmp-plugin\ndata:\n  plugin.yaml: |\n    apiVersion: argoproj.io/v1alpha1\n    kind: ConfigManagementPlugin\n    metadata:\n      name: argocd-vault-plugin\n    spec:\n      allowConcurrency: true\n      discover:\n        find:\n          command:\n            - sh\n            - \"-c\"\n            - \"find . -name \\\"*.yaml\\\"\"\n      generate:\n        command:\n          - argocd-vault-plugin\n          - generate\n          - -s\n          - vault\n          - \".\"\n      lockRepo: false\n---\napiVersion: apps/v1\nkind: Deployment\nmetadata:\n  labels:\n    app.kubernetes.io/component: repo-server\n    app.kubernetes.io/name: argocd-repo-server\n    app.kubernetes.io/part-of: argocd\n  name: argocd-repo-server\nspec:\n  selector:\n    matchLabels:\n      app.kubernetes.io/name: argocd-repo-server\n  template:\n    metadata:\n      labels:\n        app.kubernetes.io/name: argocd-repo-server\n    spec:\n      affinity:\n        podAntiAffinity:\n          preferredDuringSchedulingIgnoredDuringExecution:\n          - podAffinityTerm:\n              labelSelector:\n                matchLabels:\n                  app.kubernetes.io/name: argocd-repo-server\n              topologyKey: kubernetes.io/hostname\n            weight: 100\n          - podAffinityTerm:\n              labelSelector:\n                matchLabels:\n                  app.kubernetes.io/part-of: argocd\n              topologyKey: kubernetes.io/hostname\n            weight: 5\n      automountServiceAccountToken: true\n      containers:\n      - name: avp\n        command: [/var/run/argocd/argocd-cmp-server]\n        image: registry.access.redhat.com/ubi8\n        securityContext:\n          runAsNonRoot: true\n          runAsUser: 999\n        volumeMounts:\n          - mountPath: /var/run/argocd\n            name: var-files\n          - mountPath: /home/argocd/cmp-server/plugins\n            name: plugins\n          - mountPath: /tmp\n            name: tmp\n          # Register plugins into sidecar\n          - mountPath: /home/argocd/cmp-server/config/plugin.yaml\n            subPath: plugin.yaml\n            name: cmp-plugin\n          # Important: Mount tools into $PATH\n          - name: custom-tools\n            subPath: argocd-vault-plugin\n            mountPath: /usr/local/bin/argocd-vault-plugin\n      - args:\n        - /usr/local/bin/argocd-repo-server\n        env:\n        - name: REDIS_PASSWORD\n          valueFrom:\n            secretKeyRef:\n              key: auth\n              name: argocd-redis\n        - name: ARGOCD_RECONCILIATION_TIMEOUT\n          valueFrom:\n            configMapKeyRef:\n              key: timeout.reconciliation\n              name: argocd-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_LOGFORMAT\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.log.format\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_LOGLEVEL\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.log.level\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_LOG_FORMAT_TIMESTAMP\n          valueFrom:\n            configMapKeyRef:\n              key: log.format.timestamp\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_PARALLELISM_LIMIT\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.parallelism.limit\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_LISTEN_ADDRESS\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.listen.address\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_LISTEN_METRICS_ADDRESS\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.metrics.listen.address\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_DISABLE_TLS\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.disable.tls\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_TLS_MIN_VERSION\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.tls.minversion\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_TLS_MAX_VERSION\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.tls.maxversion\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_TLS_CIPHERS\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.tls.ciphers\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_CACHE_EXPIRATION\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.repo.cache.expiration\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: REDIS_SERVER\n          valueFrom:\n            configMapKeyRef:\n              key: redis.server\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: REDIS_COMPRESSION\n          valueFrom:\n            configMapKeyRef:\n              key: redis.compression\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: REDISDB\n          valueFrom:\n            configMapKeyRef:\n              key: redis.db\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_DEFAULT_CACHE_EXPIRATION\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.default.cache.expiration\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_OTLP_ADDRESS\n          valueFrom:\n            configMapKeyRef:\n              key: otlp.address\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_OTLP_INSECURE\n          valueFrom:\n            configMapKeyRef:\n              key: otlp.insecure\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_OTLP_HEADERS\n          valueFrom:\n            configMapKeyRef:\n              key: otlp.headers\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_OTLP_ATTRS\n          valueFrom:\n            configMapKeyRef:\n              key: otlp.attrs\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_MAX_COMBINED_DIRECTORY_MANIFESTS_SIZE\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.max.combined.directory.manifests.size\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_PLUGIN_TAR_EXCLUSIONS\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.plugin.tar.exclusions\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_PLUGIN_USE_MANIFEST_GENERATE_PATHS\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.plugin.use.manifest.generate.paths\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_ALLOW_OUT_OF_BOUNDS_SYMLINKS\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.allow.oob.symlinks\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_STREAMED_MANIFEST_MAX_TAR_SIZE\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.streamed.manifest.max.tar.size\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_STREAMED_MANIFEST_MAX_EXTRACTED_SIZE\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.streamed.manifest.max.extracted.size\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_HELM_MANIFEST_MAX_EXTRACTED_SIZE\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.helm.manifest.max.extracted.size\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_DISABLE_HELM_MANIFEST_MAX_EXTRACTED_SIZE\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.disable.helm.manifest.max.extracted.size\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_OCI_MANIFEST_MAX_EXTRACTED_SIZE\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.oci.manifest.max.extracted.size\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_DISABLE_OCI_MANIFEST_MAX_EXTRACTED_SIZE\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.disable.oci.manifest.max.extracted.size\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_OCI_LAYER_MEDIA_TYPES\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.oci.layer.media.types\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REVISION_CACHE_LOCK_TIMEOUT\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.revision.cache.lock.timeout\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_GIT_MODULES_ENABLED\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.enable.git.submodule\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_GIT_LS_REMOTE_PARALLELISM_LIMIT\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.git.lsremote.parallelism.limit\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_GIT_REQUEST_TIMEOUT\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.git.request.timeout\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_GRPC_MAX_SIZE_MB\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.grpc.max.size\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: ARGOCD_REPO_SERVER_INCLUDE_HIDDEN_DIRECTORIES\n          valueFrom:\n            configMapKeyRef:\n              key: reposerver.include.hidden.directories\n              name: argocd-cmd-params-cm\n              optional: true\n        - name: HELM_CACHE_HOME\n          value: /helm-working-dir\n        - name: HELM_CONFIG_HOME\n          value: /helm-working-dir\n        - name: HELM_DATA_HOME\n          value: /helm-working-dir\n        image: quay.io/argoproj/argocd:v3.1.5\n        imagePullPolicy: Always\n        livenessProbe:\n          failureThreshold: 3\n          httpGet:\n            path: /healthz?full=true\n            port: 8084\n          initialDelaySeconds: 30\n          periodSeconds: 30\n          timeoutSeconds: 5\n        name: argocd-repo-server\n        ports:\n        - containerPort: 8081\n        - containerPort: 8084\n        readinessProbe:\n          httpGet:\n            path: /healthz\n            port: 8084\n          initialDelaySeconds: 5\n          periodSeconds: 10\n        securityContext:\n          allowPrivilegeEscalation: false\n          capabilities:\n            drop:\n            - ALL\n          readOnlyRootFilesystem: true\n          runAsNonRoot: true\n          seccompProfile:\n            type: RuntimeDefault\n        volumeMounts:\n        - mountPath: /app/config/ssh\n          name: ssh-known-hosts\n        - mountPath: /app/config/tls\n          name: tls-certs\n        - mountPath: /app/config/gpg/source\n          name: gpg-keys\n        - mountPath: /app/config/gpg/keys\n          name: gpg-keyring\n        - mountPath: /app/config/reposerver/tls\n          name: argocd-repo-server-tls\n        - mountPath: /tmp\n          name: tmp\n        - mountPath: /helm-working-dir\n          name: helm-working-dir\n        - mountPath: /home/argocd/cmp-server/plugins\n          name: plugins\n      initContainers:\n      - name: download-tools\n        image: registry.access.redhat.com/ubi8\n        env:\n          - name: AVP_VERSION\n            value: 1.16.1\n        command: [sh, -c]\n        args:\n          - >-\n            curl -L https://github.com/argoproj-labs/argocd-vault-plugin/releases/download/v$(AVP_VERSION)/argocd-vault-plugin_$(AVP_VERSION)_linux_amd64 -o argocd-vault-plugin &&\n            chmod +x argocd-vault-plugin &&\n            mv argocd-vault-plugin /custom-tools/\n        volumeMounts:\n          - mountPath: /custom-tools\n            name: custom-tools\n      - command:\n        - /bin/cp\n        - -n\n        - /usr/local/bin/argocd\n        - /var/run/argocd/argocd-cmp-server\n        image: quay.io/argoproj/argocd:v3.1.5\n        name: copyutil\n        securityContext:\n          allowPrivilegeEscalation: false\n          capabilities:\n            drop:\n            - ALL\n          readOnlyRootFilesystem: true\n          runAsNonRoot: true\n          seccompProfile:\n            type: RuntimeDefault\n        volumeMounts:\n        - mountPath: /var/run/argocd\n          name: var-files\n      nodeSelector:\n        kubernetes.io/os: linux\n      serviceAccountName: argocd-repo-server\n      volumes:\n      - name: cmp-plugin\n        configMap:\n          name: cmp-plugin\n      - name: custom-tools\n        emptyDir: {}\n      - configMap:\n          name: argocd-ssh-known-hosts-cm\n        name: ssh-known-hosts\n      - configMap:\n          name: argocd-tls-certs-cm\n        name: tls-certs\n      - configMap:\n          name: argocd-gpg-keys-cm\n        name: gpg-keys\n      - emptyDir: {}\n        name: gpg-keyring\n      - emptyDir: {}\n        name: tmp\n      - emptyDir: {}\n        name: helm-working-dir\n      - name: argocd-repo-server-tls\n        secret:\n          items:\n          - key: tls.crt\n            path: tls.crt\n          - key: tls.key\n            path: tls.key\n          - key: ca.crt\n            path: ca.crt\n          optional: true\n          secretName: argocd-repo-server-tls\n      - emptyDir: {}\n        name: var-files\n      - emptyDir: {}\n        name: plugins\n' > manifests/argocd_vault_plugin.yaml\nkubectl -n argocd apply -f manifests/argocd_vault_plugin.yaml\nkubectl -n argocd rollout restart deployment argocd-repo-server\nkubectl -n argocd rollout restart deployment argocd-redis\nsleep 10\n\necho '#!/bin/bash\nexport ARGOCD_SERVER_DOMAIN=$(kubectl get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')\nexport ARGOCD_SERVER_PASSWORD=$(argocd admin initial-password -n argocd | cut -d \" \" -f1 | tr -d \"\\n\")\necho $ARGOCD_SERVER_PASSWORD > argocd_password.txt\nargocd login $ARGOCD_SERVER_DOMAIN --insecure --username admin --password $ARGOCD_SERVER_PASSWORD\nsleep 10\nargocd cluster add $(kubectl config get-contexts -o name) -y\nkubectl config set-context --current --namespace=argocd\nargocd app create argo-app \\\n--sync-policy automated --self-heal \\\n--repo https://github.com/${var.git_hub_user}/${var.git_hub_repo}.git \\\n--path manifest \\\n--dest-server https://kubernetes.default.svc \\\n--dest-namespace default \\\n--config-management-plugin argocd-vault-plugin\n# argocd app sync argo-app\nkubectl config set-context --current --namespace=default' > argocd.sh\nchmod +x argocd.sh\n# ./argocd.sh\n\nSSMEOF\n"])
  }
  depends_on = [aws_instance.vs_code_ec2, aws_lb.argocd, aws_lb.vault]
}
# --- Outputs ---
# CloudFormation output: VsCode
output "vs_code" {
  value       = "http://${aws_instance.vs_code_ec2.public_ip}:8000"
  description = "Public IP Address of the VS Code"
}
