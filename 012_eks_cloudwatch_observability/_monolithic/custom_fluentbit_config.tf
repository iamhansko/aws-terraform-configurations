# Generated from 012_eks_cloudwatch_observability/custom_fluentbit_config.yaml by tools/cfn2tf.
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
  default     = "custom-fluentbit-config"
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
resource "aws_iam_role_policy_attachment" "cloud_watch_observability_iam_role" {
  role       = aws_iam_role.cloud_watch_observability_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
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
# #     "Timeout": "PT30M"
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

sudo -Eu ec2-user bash << 'EOF'
cd /home/ec2-user
mkdir -p /home/ec2-user/bin
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.33.0/2025-05-01/bin/linux/amd64/kubectl
chmod +x kubectl
mv kubectl /home/ec2-user/bin/kubectl
export PATH=/home/ec2-user/bin:$PATH
echo "export PATH=/home/ec2-user/bin:$PATH" >> ~/.bashrc
echo "alias k=kubectl" >> ~/.bashrc
echo "complete -o default -F __start_kubectl k" >> ~/.bashrc
echo "source <(kubectl completion bash)" >> ~/.bashrc

aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${aws_eks_cluster.eks_cluster.name}

curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > /home/ec2-user/get_helm.sh
chmod 700 /home/ec2-user/get_helm.sh
/home/ec2-user/get_helm.sh

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource BastionEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_ec2_security_group.id, aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id]
}
resource "aws_security_group" "bastion_ec2_security_group" {
  description = "Security Group for Bastion EC2 SSH Connection"
  name        = "bastion-sg"
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 8000
    protocol    = "tcp"
    to_port     = 8000
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
resource "aws_eks_access_entry" "bastion_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  type          = "STANDARD"
}
resource "aws_eks_addon" "vpc_cni_addon" {
  addon_name                  = "vpc-cni"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "kube_proxy_addon" {
  addon_name                  = "kube-proxy"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "coredns_addon" {
  addon_name                  = "coredns"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "metrics_server_addon" {
  addon_name                  = "metrics-server"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "pod_identity_agent_addon" {
  addon_name                  = "eks-pod-identity-agent"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_node_group" "managed_node_group" {
  cluster_name   = aws_eks_cluster.eks_cluster.name
  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"
  node_role_arn  = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    min_size     = 2
    desired_size = 2
    max_size     = 2
  }
  subnet_ids = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  launch_template {
    id      = aws_launch_template.launch_template.id
    version = aws_launch_template.launch_template.latest_version
  }
  node_repair_config {
    enabled = true
  }
}
resource "aws_launch_template" "launch_template" {
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id]
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "eks-node"
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
resource "aws_eks_addon" "cloud_watch_observability_addon" {
  addon_name                  = "amazon-cloudwatch-observability"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
  pod_identity_association {
    role_arn        = aws_iam_role.cloud_watch_observability_iam_role.arn
    service_account = "cloudwatch-agent"
  }
  configuration_values = "containerLogs:\n  fluentBit:\n    config:\n      extraFiles:\n        application-log.conf: \"\"\n        dataplane-log.conf: \"\"\n        vpc-cni.conf: |\n          [INPUT]\n            Name                tail\n            Tag                 vpc-cni.*\n            Path                /var/log/containers/aws-node-*_kube-system_*.log\n            multiline.parser    docker, cri\n            DB                  /var/fluent-bit/state/flb-vpc-cni.db\n            Mem_Buf_Limit       50MB\n            Skip_Long_Lines     On\n            Refresh_Interval    10\n            Rotate_Wait         30\n            storage.type        filesystem\n            Read_from_Head      $${READ_FROM_HEAD}\n\n          [FILTER]\n            Name                kubernetes\n            Match               vpc-cni.*\n            Kube_Tag_Prefix     vpc-cni.var.log.containers.\n            Kube_URL            https://kubernetes.default.svc:443\n            Merge_Log           On\n            Merge_Log_Key       log_processed\n            K8S-Logging.Parser  On\n            K8S-Logging.Exclude Off\n            Labels              Off\n            Annotations         Off\n            Use_Kubelet         On\n            Kubelet_Port        10250\n            Buffer_Size         0\n            Use_Pod_Association On\n\n          [FILTER]\n            Name                nest\n            Match               vpc-cni.*\n            Operation           lift\n            Nested_under        kubernetes\n\n          [FILTER]\n            Name                modify\n            Match               vpc-cni.*\n            Rename              pod_name pod\n            Rename              container_name container\n            Rename              namespace_name namespace\n            Rename              host node\n\n          [FILTER]\n            Name                record_modifier\n            Match               vpc-cni.*\n            Allowlist_key       log\n            Allowlist_key       pod\n            Allowlist_key       container\n            Allowlist_key       namespace\n            Allowlist_key       node\n\n          [OUTPUT]\n            Name                cloudwatch_logs\n            Match               vpc-cni.*\n            region              $${AWS_REGION}\n            log_group_name      /aws/eks/$${CLUSTER_NAME}/vpc-cni\n            log_stream_prefix   vpc-cni-\n            log_stream_template $pod.FROM.$${HOST_NAME}\n            auto_create_group   true\n            extra_user_agent    container-insights\n            add_entity          true\n        kube-proxy.conf: |\n          [INPUT]\n            Name                tail\n            Tag                 kube-proxy.*\n            Path                /var/log/containers/kube-proxy-*_kube-system_*.log\n            multiline.parser    docker, cri\n            DB                  /var/fluent-bit/state/flb-kube-proxy.db\n            Mem_Buf_Limit       50MB\n            Skip_Long_Lines     On\n            Refresh_Interval    10\n            Rotate_Wait         30\n            storage.type        filesystem\n            Read_from_Head      $${READ_FROM_HEAD}\n\n          [FILTER]\n            Name                kubernetes\n            Match               kube-proxy.*\n            Kube_Tag_Prefix     kube-proxy.var.log.containers.\n            Kube_URL            https://kubernetes.default.svc:443\n            Merge_Log           On\n            Merge_Log_Key       log_processed\n            K8S-Logging.Parser  On\n            K8S-Logging.Exclude Off\n            Labels              Off\n            Annotations         Off\n            Use_Kubelet         On\n            Kubelet_Port        10250\n            Buffer_Size         0\n            Use_Pod_Association On\n\n          [FILTER]\n            Name                nest\n            Match               kube-proxy.*\n            Operation           lift\n            Nested_under        kubernetes\n\n          [FILTER]\n            Name                modify\n            Match               kube-proxy.*\n            Rename              pod_name pod\n            Rename              container_name container\n            Rename              namespace_name namespace\n            Rename              host node\n\n          [FILTER]\n            Name                record_modifier\n            Match               kube-proxy.*\n            Allowlist_key       log\n            Allowlist_key       pod\n            Allowlist_key       container\n            Allowlist_key       namespace\n            Allowlist_key       node\n\n          [OUTPUT]\n            Name                cloudwatch_logs\n            Match               kube-proxy.*\n            region              $${AWS_REGION}\n            log_group_name      /aws/eks/$${CLUSTER_NAME}/kube-proxy\n            log_stream_prefix   kube-proxy-\n            log_stream_template $pod.FROM.$${HOST_NAME}\n            auto_create_group   true\n            extra_user_agent    container-insights\n            add_entity          true\n        coredns.conf: |\n          [INPUT]\n            Name                tail\n            Tag                 coredns.*\n            Path                /var/log/containers/coredns-*_kube-system_*.log\n            multiline.parser    docker, cri\n            DB                  /var/fluent-bit/state/flb-coredns.db\n            Mem_Buf_Limit       50MB\n            Skip_Long_Lines     On\n            Refresh_Interval    10\n            Rotate_Wait         30\n            storage.type        filesystem\n            Read_from_Head      $${READ_FROM_HEAD}\n\n          [FILTER]\n            Name                kubernetes\n            Match               coredns.*\n            Kube_Tag_Prefix     coredns.var.log.containers.\n            Kube_URL            https://kubernetes.default.svc:443\n            Merge_Log           On\n            Merge_Log_Key       log_processed\n            K8S-Logging.Parser  On\n            K8S-Logging.Exclude Off\n            Labels              Off\n            Annotations         Off\n            Use_Kubelet         On\n            Kubelet_Port        10250\n            Buffer_Size         0\n            Use_Pod_Association On\n\n          [FILTER]\n            Name                nest\n            Match               coredns.*\n            Operation           lift\n            Nested_under        kubernetes\n\n          [FILTER]\n            Name                modify\n            Match               coredns.*\n            Rename              pod_name pod\n            Rename              container_name container\n            Rename              namespace_name namespace\n            Rename              host node\n\n          [FILTER]\n            Name                record_modifier\n            Match               coredns.*\n            Allowlist_key       log\n            Allowlist_key       pod\n            Allowlist_key       container\n            Allowlist_key       namespace\n            Allowlist_key       node\n\n          [OUTPUT]\n            Name                cloudwatch_logs\n            Match               coredns.*\n            region              $${AWS_REGION}\n            log_group_name      /aws/eks/$${CLUSTER_NAME}/coredns\n            log_stream_prefix   coredns-\n            log_stream_template $pod.FROM.$${HOST_NAME}\n            auto_create_group   true\n            extra_user_agent    container-insights\n            add_entity          true\n        metrics-server.conf: |\n          [INPUT]\n            Name                tail\n            Tag                 metrics-server.*\n            Path                /var/log/containers/metrics-server-*_kube-system_*.log\n            multiline.parser    docker, cri\n            DB                  /var/fluent-bit/state/flb-metrics-server.db\n            Mem_Buf_Limit       50MB\n            Skip_Long_Lines     On\n            Refresh_Interval    10\n            Rotate_Wait         30\n            storage.type        filesystem\n            Read_from_Head      $${READ_FROM_HEAD}\n\n          [FILTER]\n            Name                kubernetes\n            Match               metrics-server.*\n            Kube_Tag_Prefix     metrics-server.var.log.containers.\n            Kube_URL            https://kubernetes.default.svc:443\n            Merge_Log           On\n            Merge_Log_Key       log_processed\n            K8S-Logging.Parser  On\n            K8S-Logging.Exclude Off\n            Labels              Off\n            Annotations         Off\n            Use_Kubelet         On\n            Kubelet_Port        10250\n            Buffer_Size         0\n            Use_Pod_Association On\n\n          [FILTER]\n            Name                nest\n            Match               metrics-server.*\n            Operation           lift\n            Nested_under        kubernetes\n\n          [FILTER]\n            Name                modify\n            Match               metrics-server.*\n            Rename              pod_name pod\n            Rename              container_name container\n            Rename              namespace_name namespace\n            Rename              host node\n\n          [FILTER]\n            Name                record_modifier\n            Match               metrics-server.*\n            Allowlist_key       log\n            Allowlist_key       pod\n            Allowlist_key       container\n            Allowlist_key       namespace\n            Allowlist_key       node\n\n          [OUTPUT]\n            Name                cloudwatch_logs\n            Match               metrics-server.*\n            region              $${AWS_REGION}\n            log_group_name      /aws/eks/$${CLUSTER_NAME}/metrics-server\n            log_stream_prefix   metrics-server-\n            log_stream_template $pod.FROM.$${HOST_NAME}\n            auto_create_group   true\n            extra_user_agent    container-insights\n            add_entity          true\n        amazon-cloudwatch-observability.conf: |\n          [INPUT]\n            Name                tail\n            Tag                 amazon-cloudwatch-observability.*\n            Path                /var/log/containers/amazon-cloudwatch-observability-controller-manager-*_amazon-cloudwatch_*.log, /var/log/containers/cloudwatch-agent-*_amazon-cloudwatch_*.log, /var/log/containers/fluent-bit-*_amazon-cloudwatch_*.log\n            multiline.parser    docker, cri\n            DB                  /var/fluent-bit/state/flb-amazon-cloudwatch-observability.db\n            Mem_Buf_Limit       50MB\n            Skip_Long_Lines     On\n            Refresh_Interval    10\n            Rotate_Wait         30\n            storage.type        filesystem\n            Read_from_Head      $${READ_FROM_HEAD}\n\n          [FILTER]\n            Name                kubernetes\n            Match               amazon-cloudwatch-observability.*\n            Kube_Tag_Prefix     amazon-cloudwatch-observability.var.log.containers.\n            Kube_URL            https://kubernetes.default.svc:443\n            Merge_Log           On\n            Merge_Log_Key       log_processed\n            K8S-Logging.Parser  On\n            K8S-Logging.Exclude Off\n            Labels              Off\n            Annotations         Off\n            Use_Kubelet         On\n            Kubelet_Port        10250\n            Buffer_Size         0\n            Use_Pod_Association On\n\n          [FILTER]\n            Name                nest\n            Match               amazon-cloudwatch-observability.*\n            Operation           lift\n            Nested_under        kubernetes\n\n          [FILTER]\n            Name                modify\n            Match               amazon-cloudwatch-observability.*\n            Rename              pod_name pod\n            Rename              container_name container\n            Rename              namespace_name namespace\n            Rename              host node\n\n          [FILTER]\n            Name                record_modifier\n            Match               amazon-cloudwatch-observability.*\n            Allowlist_key       log\n            Allowlist_key       pod\n            Allowlist_key       container\n            Allowlist_key       namespace\n            Allowlist_key       node\n\n          [OUTPUT]\n            Name                cloudwatch_logs\n            Match               amazon-cloudwatch-observability.*\n            region              $${AWS_REGION}\n            log_group_name      /aws/eks/$${CLUSTER_NAME}/amazon-cloudwatch-observability\n            log_stream_prefix   amazon-cloudwatch-observability-\n            log_stream_template $pod.FROM.$${HOST_NAME}\n            auto_create_group   true\n            extra_user_agent    container-insights\n            add_entity          true\n        aws-efs-csi-driver.conf: |\n          [INPUT]\n            Name                tail\n            Tag                 aws-efs-csi-driver.*\n            Path                /var/log/containers/efs-csi-controller-*_kube-system_*.log, /var/log/containers/efs-csi-node-*_kube-system_*.log\n            multiline.parser    docker, cri\n            DB                  /var/fluent-bit/state/flb-aws-efs-csi-driver.db\n            Mem_Buf_Limit       50MB\n            Skip_Long_Lines     On\n            Refresh_Interval    10\n            Rotate_Wait         30\n            storage.type        filesystem\n            Read_from_Head      $${READ_FROM_HEAD}\n\n          [FILTER]\n            Name                kubernetes\n            Match               aws-efs-csi-driver.*\n            Kube_Tag_Prefix     aws-efs-csi-driver.var.log.containers.\n            Kube_URL            https://kubernetes.default.svc:443\n            Merge_Log           On\n            Merge_Log_Key       log_processed\n            K8S-Logging.Parser  On\n            K8S-Logging.Exclude Off\n            Labels              Off\n            Annotations         Off\n            Use_Kubelet         On\n            Kubelet_Port        10250\n            Buffer_Size         0\n            Use_Pod_Association On\n\n          [FILTER]\n            Name                nest\n            Match               aws-efs-csi-driver.*\n            Operation           lift\n            Nested_under        kubernetes\n\n          [FILTER]\n            Name                modify\n            Match               aws-efs-csi-driver.*\n            Rename              pod_name pod\n            Rename              container_name container\n            Rename              namespace_name namespace\n            Rename              host node\n\n          [FILTER]\n            Name                record_modifier\n            Match               aws-efs-csi-driver.*\n            Allowlist_key       log\n            Allowlist_key       pod\n            Allowlist_key       container\n            Allowlist_key       namespace\n            Allowlist_key       node\n\n          [OUTPUT]\n            Name                cloudwatch_logs\n            Match               aws-efs-csi-driver.*\n            region              $${AWS_REGION}\n            log_group_name      /aws/eks/$${CLUSTER_NAME}/aws-efs-csi-driver\n            log_stream_prefix   aws-efs-csi-driver-\n            log_stream_template $pod.FROM.$${HOST_NAME}\n            auto_create_group   true\n            extra_user_agent    container-insights\n            add_entity          true\n        cluster-autoscaler.conf: |\n          [INPUT]\n            Name                tail\n            Tag                 cluster-autoscaler.*\n            Path                /var/log/containers/cluster-autoscaler-*_kube-system_*.log\n            multiline.parser    docker, cri\n            DB                  /var/fluent-bit/state/flb-cluster-autoscaler.db\n            Mem_Buf_Limit       50MB\n            Skip_Long_Lines     On\n            Refresh_Interval    10\n            Rotate_Wait         30\n            storage.type        filesystem\n            Read_from_Head      $${READ_FROM_HEAD}\n\n          [FILTER]\n            Name                kubernetes\n            Match               cluster-autoscaler.*\n            Kube_Tag_Prefix     cluster-autoscaler.var.log.containers.\n            Kube_URL            https://kubernetes.default.svc:443\n            Merge_Log           On\n            Merge_Log_Key       log_processed\n            K8S-Logging.Parser  On\n            K8S-Logging.Exclude Off\n            Labels              Off\n            Annotations         Off\n            Use_Kubelet         On\n            Kubelet_Port        10250\n            Buffer_Size         0\n            Use_Pod_Association On\n\n          [FILTER]\n            Name                nest\n            Match               cluster-autoscaler.*\n            Operation           lift\n            Nested_under        kubernetes\n\n          [FILTER]\n            Name                modify\n            Match               cluster-autoscaler.*\n            Rename              pod_name pod\n            Rename              container_name container\n            Rename              namespace_name namespace\n            Rename              host node\n\n          [FILTER]\n            Name                record_modifier\n            Match               cluster-autoscaler.*\n            Allowlist_key       log\n            Allowlist_key       pod\n            Allowlist_key       container\n            Allowlist_key       namespace\n            Allowlist_key       node\n\n          [OUTPUT]\n            Name                cloudwatch_logs\n            Match               cluster-autoscaler.*\n            region              $${AWS_REGION}\n            log_group_name      /aws/eks/$${CLUSTER_NAME}/cluster-autoscaler\n            log_stream_prefix   cluster-autoscaler-\n            log_stream_template $pod.FROM.$${HOST_NAME}\n            auto_create_group   true\n            extra_user_agent    container-insights\n            add_entity          true\n        aws-load-balancer-controller.conf: |\n          [INPUT]\n            Name                tail\n            Tag                 aws-load-balancer-controller.*\n            Path                /var/log/containers/aws-load-balancer-controller-*_kube-system_*.log\n            multiline.parser    docker, cri\n            DB                  /var/fluent-bit/state/flb-aws-load-balancer-controller.db\n            Mem_Buf_Limit       50MB\n            Skip_Long_Lines     On\n            Refresh_Interval    10\n            Rotate_Wait         30\n            storage.type        filesystem\n            Read_from_Head      $${READ_FROM_HEAD}\n\n          [FILTER]\n            Name                kubernetes\n            Match               aws-load-balancer-controller.*\n            Kube_Tag_Prefix     aws-load-balancer-controller.var.log.containers.\n            Kube_URL            https://kubernetes.default.svc:443\n            Merge_Log           On\n            Merge_Log_Key       log_processed\n            K8S-Logging.Parser  On\n            K8S-Logging.Exclude Off\n            Labels              Off\n            Annotations         Off\n            Use_Kubelet         On\n            Kubelet_Port        10250\n            Buffer_Size         0\n            Use_Pod_Association On\n\n          [FILTER]\n            Name                nest\n            Match               aws-load-balancer-controller.*\n            Operation           lift\n            Nested_under        kubernetes\n\n          [FILTER]\n            Name                modify\n            Match               aws-load-balancer-controller.*\n            Rename              pod_name pod\n            Rename              container_name container\n            Rename              namespace_name namespace\n            Rename              host node\n\n          [FILTER]\n            Name                record_modifier\n            Match               aws-load-balancer-controller.*\n            Allowlist_key       log\n            Allowlist_key       pod\n            Allowlist_key       container\n            Allowlist_key       namespace\n            Allowlist_key       node\n\n          [OUTPUT]\n            Name                cloudwatch_logs\n            Match               aws-load-balancer-controller.*\n            region              $${AWS_REGION}\n            log_group_name      /aws/eks/$${CLUSTER_NAME}/aws-load-balancer-controller\n            log_stream_prefix   aws-load-balancer-controller-\n            log_stream_template $pod.FROM.$${HOST_NAME}\n            auto_create_group   true\n            extra_user_agent    container-insights\n            add_entity          true\n"
  depends_on           = [aws_eks_addon.pod_identity_agent_addon]
}
resource "aws_iam_role" "cloud_watch_observability_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["pods.eks.amazonaws.com"]
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
# --- Outputs ---
# CloudFormation output: VsCode
output "vs_code" {
  value       = "http://${aws_instance.bastion_ec2.public_ip}:8000"
  description = "VsCode on BastionEC2"
}
