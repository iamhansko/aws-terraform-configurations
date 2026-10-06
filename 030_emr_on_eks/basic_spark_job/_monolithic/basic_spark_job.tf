# Generated from 030_emr_on_eks/basic_spark_job.yaml by tools/cfn2tf.
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
  default     = "basic-spark-job"
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
    AWSRegions2PrefixListID = {
      "ap-northeast-1" = {
        PrefixList = "pl-58a04531"
      }
      "ap-northeast-2" = {
        PrefixList = "pl-22a6434b"
      }
      "ap-northeast-3" = {
        PrefixList = "pl-31a14458"
      }
      "ap-south-1" = {
        PrefixList = "pl-9aa247f3"
      }
      "ap-southeast-1" = {
        PrefixList = "pl-31a34658"
      }
      "ap-southeast-2" = {
        PrefixList = "pl-b8a742d1"
      }
      "ca-central-1" = {
        PrefixList = "pl-38a64351"
      }
      "eu-central-1" = {
        PrefixList = "pl-a3a144ca"
      }
      "eu-north-1" = {
        PrefixList = "pl-fab65393"
      }
      "eu-west-1" = {
        PrefixList = "pl-4fa04526"
      }
      "eu-west-2" = {
        PrefixList = "pl-93a247fa"
      }
      "eu-west-3" = {
        PrefixList = "pl-75b1541c"
      }
      "sa-east-1" = {
        PrefixList = "pl-5da64334"
      }
      "us-east-1" = {
        PrefixList = "pl-3b927c52"
      }
      "us-east-2" = {
        PrefixList = "pl-b6a144df"
      }
      "us-west-1" = {
        PrefixList = "pl-4ea04527"
      }
      "us-west-2" = {
        PrefixList = "pl-82a045eb"
      }
    }
  }
  stack_id = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
}
# --- Resources split out of composite CloudFormation resources ---
resource "aws_iam_role_policy_attachment" "bastion_ec2_iam_role" {
  role       = aws_iam_role.bastion_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
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
resource "aws_iam_role_policy_attachment" "eks_cluster_iam_role" {
  role       = aws_iam_role.eks_cluster_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
resource "aws_eks_access_policy_association" "bastion_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}
resource "aws_iam_role_policy_attachment" "core_node_iam_role_0" {
  role       = aws_iam_role.core_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
resource "aws_iam_role_policy_attachment" "core_node_iam_role_1" {
  role       = aws_iam_role.core_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
resource "aws_iam_role_policy_attachment" "core_node_iam_role_2" {
  role       = aws_iam_role.core_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
resource "aws_iam_role_policy_attachment" "core_node_iam_role_3" {
  role       = aws_iam_role.core_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "karpenter_controller_iam_role" {
  role       = aws_iam_role.karpenter_controller_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_iam_role_policy_attachment" "karpenter_node_iam_role_0" {
  role       = aws_iam_role.karpenter_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
resource "aws_iam_role_policy_attachment" "karpenter_node_iam_role_1" {
  role       = aws_iam_role.karpenter_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
resource "aws_iam_role_policy_attachment" "karpenter_node_iam_role_2" {
  role       = aws_iam_role.karpenter_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
resource "aws_iam_role_policy_attachment" "karpenter_node_iam_role_3" {
  role       = aws_iam_role.karpenter_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy" "cluster_autoscaler_role" {
  name = "ClusterAutoscalerPolicy"
  role = aws_iam_role.cluster_autoscaler_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["autoscaling:SetDesiredCapacity", "autoscaling:TerminateInstanceInAutoScalingGroup"]
      Resource = "*"
      Condition = {
        StringEquals = {
          "aws:ResourceTag/k8s.io/cluster-autoscaler/enabled" = "true"
        }
      }
      }, {
      Effect   = "Allow"
      Action   = ["autoscaling:DescribeAutoScalingInstances", "autoscaling:DescribeAutoScalingGroups", "ec2:DescribeLaunchTemplateVersions", "autoscaling:DescribeTags", "autoscaling:DescribeLaunchConfigurations", "ec2:DescribeInstanceTypes", "autoscaling:DescribeScalingActivities", "ec2:DescribeImages", "ec2:GetInstanceTypesFromInstanceRequirements", "eks:DescribeNodegroup"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy" "emr_job_execution_role" {
  name = "EmrJobExecutionPolicy"
  role = aws_iam_role.emr_job_execution_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
      Resource = "*"
      }, {
      Effect   = "Allow"
      Action   = ["logs:PutLogEvents", "logs:CreateLogStream", "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
      Resource = "arn:aws:logs:*:*:*"
    }]
  })
}
# --- Resources ---
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
# #     "Timeout": "PT20M"
# #   }
# # }
resource "aws_instance" "bastion_ec2" {
  instance_type        = "t3.medium"
  key_name             = aws_key_pair.key_pair.key_name
  ami                  = data.aws_ssm_parameter.amazon_linux2023_ami_id.insecure_value
  iam_instance_profile = aws_iam_instance_profile.bastion_ec2_instance_profile.name
  tags = {
    Name = "bastion"
  }
  user_data                   = <<EOT
#!/bin/bash
dnf update -yq
dnf groupinstall -yq "Development Tools"
dnf install -yq python3.13
ln -sf /usr/bin/python3.13 /usr/bin/python
python -m ensurepip --upgrade

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

dnf install -yq git
dnf install -yq docker
dnf install -yq bash-completion
systemctl enable --now docker
# usermod -aG docker ec2-user
# newgrp docker
chmod 666 /var/run/docker.sock

su - ec2-user << 'EOF'
export HOME=/home/ec2-user
cd $HOME
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.33.0/2025-05-01/bin/linux/amd64/kubectl
chmod +x ./kubectl
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH
echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -o default -F __start_kubectl k' >>~/.bashrc

ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

aws eks update-kubeconfig --name ${aws_eks_cluster.eks_cluster.name}

# helm repo add autoscaler https://kubernetes.github.io/autoscaler
# helm repo update autoscaler
# helm install cluster-autoscaler autoscaler/cluster-autoscaler -n kube-system \
# --set fullnameOverride="cluster-autoscaler" \
# --set cloudProvider=aws \
# --set autoDiscovery.clusterName=${aws_eks_cluster.eks_cluster.name} \
# --set awsRegion=${data.aws_region.current.region} \
# --set resources.limits.cpu="1000m" \
# --set resources.limits.memory="1G" \
# --set resources.requests.cpu="200m" \
# --set resources.requests.memory="512Mi" \
# --set updateStrategy.type="RollingUpdate" \
# --set updateStrategy.rollingUpdate.maxSurge=0 \
# --set updateStrategy.rollingUpdate.maxUnavailable=1 \
# --set rbac.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${aws_iam_role.cluster_autoscaler_role.arn}"
# kubectl rollout status -n kube-system deployment cluster-autoscaler

echo $'#!/bin/bash
export KARPENTER_NAMESPACE="kube-system"
export KARPENTER_VERSION="1.6.0"
export K8S_VERSION="1.33"
export AWS_PARTITION="aws"
export CLUSTER_NAME="${aws_eks_cluster.eks_cluster.name}"
export AWS_DEFAULT_REGION="${data.aws_region.current.region}"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export TEMPOUT="$(mktemp)"
helm registry logout public.ecr.aws
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
--version "$KARPENTER_VERSION" \
--namespace "$KARPENTER_NAMESPACE" --create-namespace \
--set "settings.clusterName=$CLUSTER_NAME" \
--set controller.resources.requests.cpu=1 \
--set controller.resources.requests.memory=1Gi \
--set controller.resources.limits.cpu=1 \
--set controller.resources.limits.memory=1Gi \
--set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${aws_iam_role.karpenter_controller_iam_role.arn}" \
--wait' > install_karpenter.sh
chmod +x install_karpenter.sh
./install_karpenter.sh

kubectl create namespace big-data
EOF

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource BastionEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_ec2_security_group.id]
}
resource "aws_security_group" "bastion_ec2_security_group" {
  description = "Security Group for Bastion EC2 SSH Connection"
  name        = "bastion-sg"
  ingress {
    description     = "com.amazonaws.global.cloudfront.origin-facing"
    protocol        = "tcp"
    from_port       = 8000
    to_port         = 8000
    prefix_list_ids = [local.mappings["AWSRegions2PrefixListID"][data.aws_region.current.region]["PrefixList"]]
  }
  vpc_id = aws_vpc.vpc.id
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
  role = jsonencode([aws_iam_role.bastion_ec2_iam_role.name])
}
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_cloudfront_distribution" "cloud_front_distribution" {
  origin {
    domain_name = aws_instance.bastion_ec2.public_dns
    origin_id   = aws_instance.bastion_ec2.public_dns
    custom_origin_config {
      http_port              = 8000
      origin_protocol_policy = "http-only"
      # cfn2tf: 'https_port' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using a provider-compatible default.
      https_port = 443
      # cfn2tf: 'origin_ssl_protocols' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using a provider-compatible default.
      origin_ssl_protocols = ["TLSv1.2"]
    }
  }
  enabled = true
  default_cache_behavior {
    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    forwarded_values {
      query_string = false
      # cfn2tf: 'cookies' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using the service default.
      cookies {
        forward = "none"
      }
    }
    compress                 = false
    target_origin_id         = aws_instance.bastion_ec2.public_dns
    viewer_protocol_policy   = "allow-all"
    cache_policy_id          = aws_cloudfront_cache_policy.cloud_front_cache_policy.id
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    # cfn2tf: 'cached_methods' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using a provider-compatible default.
    cached_methods = ["GET", "HEAD"]
  }
  # cfn2tf: 'restrictions' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using the service default.
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  # cfn2tf: 'viewer_certificate' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using the service default.
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
resource "aws_cloudfront_cache_policy" "cloud_front_cache_policy" {
  default_ttl = 86400
  max_ttl     = 31536000
  min_ttl     = 1
  name        = "VSCode-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "all"
    }
    enable_accept_encoding_gzip = false
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Accept-Charset", "Authorization", "Origin", "Accept", "Referer", "Host", "Accept-Language", "Accept-Encoding", "Accept-Datetime"]
      }
    }
    query_strings_config {
      query_string_behavior = "all"
    }
  }
}
resource "aws_eks_cluster" "eks_cluster" {
  version = "1.33"
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
  upgrade_policy {
    support_type = "STANDARD"
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
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url            = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_eks_access_entry" "bastion_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  type          = "STANDARD"
}
resource "aws_vpc_security_group_ingress_rule" "bastion_ec2_security_group_ingress" {
  security_group_id            = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  ip_protocol                  = -1
  referenced_security_group_id = aws_security_group.bastion_ec2_security_group.id
}
resource "aws_eks_node_group" "core_node_group" {
  node_group_name      = "core"
  ami_type             = "AL2023_x86_64_STANDARD"
  instance_types       = ["t3.medium"]
  capacity_type        = "ON_DEMAND"
  cluster_name         = aws_eks_cluster.eks_cluster.name
  force_update_version = true
  labels = {
    "node-type" = "core"
  }
  node_role_arn = aws_iam_role.core_node_iam_role.arn
  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }
  subnet_ids = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  launch_template {
    id      = aws_launch_template.core_launch_template.id
    version = aws_launch_template.core_launch_template.latest_version
  }
}
resource "aws_launch_template" "core_launch_template" {
  name                   = "core-nodegroup-launchtemplate"
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id]
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "core-node"
    }
  }
}
resource "aws_iam_role" "core_node_iam_role" {
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
resource "aws_ssm_association" "ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 600
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << 'SSMEOF'\nexport HOME=/home/ec2-user\ncd $HOME\naws eks update-kubeconfig --name ${aws_eks_cluster.eks_cluster.name}\naws iam create-service-linked-role --aws-service-name spot.amazonaws.com || true\n\nmkdir -p /home/ec2-user/manifests/spark\necho 'apiVersion: karpenter.sh/v1\nkind: NodePool\nmetadata:\n  name: g5-gpu-karpenter\nspec:\n  template:\n    metadata:\n      labels:\n        nodegroup: g5-gpu\n        type: karpenter\n    spec:\n      nodeClassRef:\n        group: karpenter.k8s.aws\n        kind: EC2NodeClass\n        name: g5-gpu-karpenter\n      requirements:\n        - key: karpenter.k8s.aws/instance-family\n          operator: In\n          values:\n          - g5\n        - key: karpenter.k8s.aws/instance-size\n          operator: In\n          values:\n          - 2xlarge\n          - 4xlarge\n          - 8xlarge\n          - 12xlarge\n          - 16xlarge\n          - 24xlarge\n          - 48xlarge\n        - key: kubernetes.io/arch\n          operator: In\n          values:\n          - amd64\n        - key: karpenter.sh/capacity-type\n          operator: In\n          values:\n          - spot\n          - on-demand\n        taints:\n        - effect: NoSchedule\n          key: nvidia.com/gpu\n          value: Exists\n  disruption:\n    budgets:\n      - nodes: 10%\n    consolidateAfter: 300s\n    consolidationPolicy: WhenEmpty\n  limits:\n    cpu: 1000\n    memory: 1000Gi\n---\napiVersion: karpenter.k8s.aws/v1\nkind: EC2NodeClass\nmetadata:\n  name: g5-gpu-karpenter\nspec:\n  amiFamily: Bottlerocket\n  amiSelectorTerms:\n  - alias: bottlerocket@latest\n  blockDeviceMappings:\n  - deviceName: /dev/xvda\n    ebs:\n      encrypted: true\n      volumeSize: 50Gi\n      volumeType: gp3\n  - deviceName: /dev/xvdb\n    ebs:\n      encrypted: true\n      volumeSize: 300Gi\n      volumeType: gp3\n  detailedMonitoring: true\n  instanceStorePolicy: RAID0\n  metadataOptions:\n    httpEndpoint: enabled\n    httpProtocolIPv6: disabled\n    httpPutResponseHopLimit: 2\n    httpTokens: required\n  subnetSelectorTerms:\n    - id: ${aws_subnet.private_subneta.id}\n    - id: ${aws_subnet.private_subnetb.id}\n  securityGroupSelectorTerms:\n    - id: ${aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id}\n  instanceProfile: ${aws_iam_instance_profile.karpenter_node_instance_profile.name}\n  tags:\n    Name: g5-gpu-karpenter' > /home/ec2-user/manifests/g5-gpu-karpenter.yaml\n\necho 'apiVersion: karpenter.sh/v1\nkind: NodePool\nmetadata:\n  name: g6-gpu-karpenter\nspec:\n  template:\n    metadata:\n      labels:\n        nodegroup: g6-gpu\n        type: karpenter\n    spec:\n      nodeClassRef:\n        group: karpenter.k8s.aws\n        kind: EC2NodeClass\n        name: g6-gpu-karpenter\n      requirements:\n        - key: karpenter.k8s.aws/instance-family\n          operator: In\n          values:\n            - g6\n        - key: karpenter.k8s.aws/instance-size\n          operator: In\n          values:\n            - 2xlarge\n            - 4xlarge\n            - 8xlarge\n            - 12xlarge\n            - 16xlarge\n            - 24xlarge\n            - 48xlarge\n        - key: kubernetes.io/arch\n          operator: In\n          values:\n            - amd64\n        - key: karpenter.sh/capacity-type\n          operator: In\n          values:\n            - spot\n            - on-demand\n      taints:\n        - effect: NoSchedule\n          key: nvidia.com/gpu\n          value: Exists\n  disruption:\n    budgets:\n    - nodes: 10%\n    consolidateAfter: 300s\n    consolidationPolicy: WhenEmpty\n  limits:\n    cpu: 1000\n    memory: 1000Gi\n---\napiVersion: karpenter.k8s.aws/v1\nkind: EC2NodeClass\nmetadata:\n  name: g6-gpu-karpenter\nspec:\n  amiFamily: Bottlerocket\n  amiSelectorTerms:\n  - alias: bottlerocket@latest\n  blockDeviceMappings:\n  - deviceName: /dev/xvda\n    ebs:\n      encrypted: true\n      volumeSize: 50Gi\n      volumeType: gp3\n  detailedMonitoring: true\n  instanceStorePolicy: RAID0\n  metadataOptions:\n    httpEndpoint: enabled\n    httpProtocolIPv6: disabled\n    httpPutResponseHopLimit: 2\n    httpTokens: required\n  subnetSelectorTerms:\n    - id: ${aws_subnet.private_subneta.id}\n    - id: ${aws_subnet.private_subnetb.id}\n  securityGroupSelectorTerms:\n    - id: ${aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id}\n  instanceProfile: ${aws_iam_instance_profile.karpenter_node_instance_profile.name}\n  tags:\n    Name: g6-gpu-karpenter' > /home/ec2-user/manifests/g6-gpu-karpenter.yaml\n\necho 'apiVersion: karpenter.sh/v1\nkind: NodePool\nmetadata:\n  name: x86-cpu-karpenter\nspec:\n  template:\n    metadata:\n      labels:\n        nodegroup: x86-cpu\n        type: karpenter\n    spec:\n      nodeClassRef:\n        group: karpenter.k8s.aws\n        kind: EC2NodeClass\n        name: x86-cpu-karpenter\n      requirements:\n        - key: karpenter.k8s.aws/instance-family\n          operator: In\n          values:\n          - m5\n        - key: karpenter.k8s.aws/instance-size\n          operator: In\n          values:\n            - xlarge\n            - 2xlarge\n            - 4xlarge\n            - 8xlarge\n        - key: kubernetes.io/arch\n          operator: In\n          values:\n            - amd64\n        - key: karpenter.sh/capacity-type\n          operator: In\n          values:\n            - spot\n            - on-demand\n  disruption:\n    budgets:\n    - nodes: 10%\n    consolidateAfter: 300s\n    consolidationPolicy: WhenEmpty\n  limits:\n    cpu: 1000\n    memory: 1000Gi\n---\napiVersion: karpenter.k8s.aws/v1\nkind: EC2NodeClass\nmetadata:\n  name: x86-cpu-karpenter\nspec:\n  amiFamily: Bottlerocket\n  amiSelectorTerms:\n  - alias: bottlerocket@latest\n  blockDeviceMappings:\n  - deviceName: /dev/xvda\n    ebs:\n      encrypted: true\n      volumeSize: 100Gi\n      volumeType: gp3\n  - deviceName: /dev/xvdb\n    ebs:\n      encrypted: true\n      volumeSize: 300Gi\n      volumeType: gp3\n  detailedMonitoring: true\n  metadataOptions:\n    httpEndpoint: enabled\n    httpProtocolIPv6: disabled\n    httpPutResponseHopLimit: 2\n    httpTokens: required\n  subnetSelectorTerms:\n    - id: ${aws_subnet.private_subneta.id}\n    - id: ${aws_subnet.private_subnetb.id}\n  securityGroupSelectorTerms:\n    - id: ${aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id}\n  instanceProfile: ${aws_iam_instance_profile.karpenter_node_instance_profile.name}\n  tags:\n    Name: x86-cpu-karpenter' > /home/ec2-user/manifests/x86-cpu-karpenter.yaml\n\nkubectl apply -f /home/ec2-user/manifests\nkubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.1/deployments/static/nvidia-device-plugin.yml\n\necho $'#!/bin/bash\nexport AWS_REGION=\"${data.aws_region.current.region}\"\nexport S3_BUCKET=\"s3://${aws_s3_bucket.emr_s3_bucket.id}\"\nexport EMR_VIRTUAL_CLUSTER_ID=\"${aws_emrcontainers_virtual_cluster.emr_virtual_cluster.id}\"\nexport EMR_EXECUTION_ROLE_ARN=\"${aws_iam_role.emr_job_execution_role.arn}\"\nexport CLOUDWATCH_LOG_GROUP=\"${aws_cloudwatch_log_group.emr_cloud_watch_log_group.name}\"\nJOB_NAME=\"taxidata\"\nEMR_EKS_RELEASE_LABEL=\"emr-6.10.0-latest\" # Spark 3.3.1\nSPARK_JOB_S3_PATH=\"$S3_BUCKET/$EMR_VIRTUAL_CLUSTER_ID/$JOB_NAME\"\nSCRIPTS_S3_PATH=\"$SPARK_JOB_S3_PATH/scripts\"\nINPUT_DATA_S3_PATH=\"$SPARK_JOB_S3_PATH/input\"\nOUTPUT_DATA_S3_PATH=\"$SPARK_JOB_S3_PATH/output\"\necho $SCRIPTS_S3_PATH\naws s3 sync \"./\" $SCRIPTS_S3_PATH\nmkdir -p \"../input\"\nwget https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-01.parquet -O \"../input/yellow_tripdata_2022-0.parquet\"\nmax=20\nfor (( i=1; i <= $max; ++i ))\ndo\ncp -rf \"../input/yellow_tripdata_2022-0.parquet\" \"../input/yellow_tripdata_2022-$i.parquet\"\ndone\naws s3 sync \"../input\" $INPUT_DATA_S3_PATH\nrm -rf \"../input\"\naws emr-containers start-job-run \\\n--virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID \\\n--name $JOB_NAME \\\n--region $AWS_REGION \\\n--execution-role-arn $EMR_EXECUTION_ROLE_ARN \\\n--release-label $EMR_EKS_RELEASE_LABEL \\\n--job-driver \\'{\n  \"sparkSubmitJobDriver\": {\n    \"entryPoint\": \"\\'\"$SCRIPTS_S3_PATH\"\\'/pyspark-taxi-trip.py\",\n    \"entryPointArguments\": [\"\\'\"$INPUT_DATA_S3_PATH\"\\'\",\n      \"\\'\"$OUTPUT_DATA_S3_PATH\"\\'\"\n    ],\n    \"sparkSubmitParameters\": \"--conf spark.executor.instances=2\"\n  }\n}\\' \\\n--configuration-overrides \\'{\n  \"applicationConfiguration\": [\n      {\n        \"classification\": \"spark-defaults\",\n        \"properties\": {\n          \"spark.driver.cores\":\"1\",\n          \"spark.executor.cores\":\"1\",\n          \"spark.driver.memory\": \"4g\",\n          \"spark.executor.memory\": \"4g\",\n          \"spark.kubernetes.driver.podTemplateFile\":\"\\'\"$SCRIPTS_S3_PATH\"\\'/driver-pod-template.yaml\",\n          \"spark.kubernetes.executor.podTemplateFile\":\"\\'\"$SCRIPTS_S3_PATH\"\\'/executor-pod-template.yaml\",\n          \"spark.local.dir\":\"/data1\",\n          \"spark.kubernetes.submission.connectionTimeout\": \"60000000\",\n          \"spark.kubernetes.submission.requestTimeout\": \"60000000\",\n          \"spark.kubernetes.driver.connectionTimeout\": \"60000000\",\n          \"spark.kubernetes.driver.requestTimeout\": \"60000000\",\n          \"spark.kubernetes.executor.podNamePrefix\":\"\\'\"$JOB_NAME\"\\'\",\n          \"spark.metrics.appStatusSource.enabled\":\"true\"\n        }\n      }\n    ],\n  \"monitoringConfiguration\": {\n    \"persistentAppUI\":\"ENABLED\",\n    \"cloudWatchMonitoringConfiguration\": {\n      \"logGroupName\":\"\\'\"$CLOUDWATCH_LOG_GROUP\"\\'\",\n      \"logStreamNamePrefix\":\"\\'\"$JOB_NAME\"\\'\"\n    },\n    \"s3MonitoringConfiguration\": {\n      \"logUri\":\"\\'\"$S3_BUCKET/logs/\"\\'\"\n    }\n  }\n}\\'' > /home/ec2-user/manifests/spark/job.sh\nchmod +x /home/ec2-user/manifests/spark/job.sh\n\necho 'import logging\nimport sys\nfrom datetime import datetime\nfrom pyspark.sql import SparkSession\nfrom pyspark.sql.functions import *\nfrom pyspark.sql import functions as f\nformatter = logging.Formatter(\"[%(asctime)s] %(levelname)s @ line %(lineno)d: %(message)s\")\nhandler = logging.StreamHandler(sys.stdout)\nhandler.setLevel(logging.INFO)\nhandler.setFormatter(formatter)\nlogger = logging.getLogger()\nlogger.setLevel(logging.INFO)\nlogger.addHandler(handler)\ndt_string = datetime.now().strftime(\"%Y_%m_%d_%H_%M_%S\")\nAppName = \"NewYorkTaxiData\"\ndef main(args):\n    raw_input_folder = args[1]\n    transform_output_folder = args[2]\n    spark = SparkSession \\\n        .builder \\\n        .appName(AppName + \"_\" + str(dt_string)) \\\n        .getOrCreate()\n    spark.sparkContext.setLogLevel(\"INFO\")\n    logger.info(\"Starting spark application\")\n    logger.info(\"Reading Parquet file from S3\")\n    ny_taxi_df = spark.read.parquet(raw_input_folder)\n    final_ny_taxi_df = ny_taxi_df.withColumn(\"current_date\", f.lit(datetime.now()))\n    logger.info(\"NewYork Taxi data schema preview\")\n    final_ny_taxi_df.printSchema()\n    logger.info(\"Previewing New York Taxi data sample\")\n    final_ny_taxi_df.show(20, truncate=False)\n    logger.info(\"Total number of records: \" + str(final_ny_taxi_df.count()))\n    logger.info(\"Write New York Taxi data to S3 transform table\")\n    final_ny_taxi_df.repartition(2).write.mode(\"overwrite\").parquet(transform_output_folder)\n    logger.info(\"Ending spark application\")\n    spark.stop()\n    return None\nif __name__ == \"__main__\":\n    print(len(sys.argv))\n    if len(sys.argv) != 3:\n        print(\"Usage: spark-etl [input-folder] [output-folder]\")\n        sys.exit(0)\n    main(sys.argv)' > /home/ec2-user/manifests/spark/pyspark-taxi-trip.py\n\necho 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: ny-taxi-driver\n  namespace: big-data\nspec:\n  nodeSelector:\n    nodegroup: x86-cpu\n    type: karpenter\n  initContainers:\n    - name: volume-permission\n      image: public.ecr.aws/docker/library/busybox\n      command: [\"sh\", \"-c\", \"mkdir /data1; chown -R 999:1000 /data1\"]\n  containers:\n    - name: spark-kubernetes-driver' > /home/ec2-user/manifests/spark/driver-pod-template.yaml\n\necho 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: ny-taxi-exec\n  namespace: big-data\nspec:\n  nodeSelector:\n    nodegroup: x86-cpu\n    type: karpenter\n  initContainers:\n    - name: volume-permission\n      image: public.ecr.aws/docker/library/busybox\n      command: [\"sh\", \"-c\", \"mkdir /data1; chown -R 999:1000 /data1\"]\n  containers:\n    - name: spark-kubernetes-executor' > /home/ec2-user/manifests/spark/executor-pod-template.yaml\nSSMEOF\n"])
  }
  depends_on = [aws_instance.bastion_ec2]
}
resource "aws_iam_role" "karpenter_controller_iam_role" {
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
                  "${element(split("//", aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer), 1)}:sub": "system:serviceaccount:kube-system:karpenter",
                  "${element(split("//", aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer), 1)}:aud": "sts.amazonaws.com"
              }
          }
      }
  ]
}
EOT
}
resource "aws_iam_role" "karpenter_node_iam_role" {
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
resource "aws_iam_instance_profile" "karpenter_node_instance_profile" {
  role = jsonencode([aws_iam_role.karpenter_node_iam_role.name])
}
resource "aws_eks_access_entry" "karpenter_node_iam_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.karpenter_node_iam_role.arn
  type          = "EC2_LINUX"
}
resource "aws_iam_role" "cluster_autoscaler_role" {
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
                  "${element(split("//", aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer), 1)}:sub": "system:serviceaccount:kube-system:cluster-autoscaler",
                  "${element(split("//", aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer), 1)}:aud": "sts.amazonaws.com"
              }
          }
      }
  ]
}
EOT
}
resource "aws_emrcontainers_virtual_cluster" "emr_virtual_cluster" {
  container_provider {
    id = aws_eks_cluster.eks_cluster.name
    info {
      eks_info {
        namespace = "big-data"
      }
    }
    type = "EKS"
  }
  name       = "big-data-cluster"
  depends_on = [aws_eks_node_group.core_node_group, aws_instance.bastion_ec2]
}
resource "aws_iam_role" "emr_job_execution_role" {
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
              "StringLike": {
                  "${element(split("//", aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer), 1)}:sub": "system:serviceaccount:big-data:emr-containers-sa-*"
              }
          }
      }
  ]
}
EOT
}
resource "aws_s3_bucket" "emr_s3_bucket" {}
resource "aws_cloudwatch_log_group" "emr_cloud_watch_log_group" {
  name = "/emr/on/eks"
}
# --- Outputs ---
# CloudFormation output: VsCode
output "vs_code" {
  value       = "https://${aws_cloudfront_distribution.cloud_front_distribution.domain_name}"
  description = "VsCode on BastionEC2"
}
