# Generated from 018_eks_node_monitoring_agent/nma.yaml by tools/cfn2tf.
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
  default     = "nma"
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
resource "aws_eks_access_policy_association" "fork_failed_out_of_p_id_bastion_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.fork_failed_out_of_p_id_eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}
resource "aws_iam_role_policy_attachment" "fork_failed_out_of_p_id_karpenter_controller_iam_role" {
  role       = aws_iam_role.fork_failed_out_of_p_id_karpenter_controller_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_eks_access_policy_association" "interface_not_up_bastion_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.interface_not_up_eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}
resource "aws_iam_role_policy_attachment" "interface_not_up_karpenter_controller_iam_role" {
  role       = aws_iam_role.interface_not_up_karpenter_controller_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_eks_access_policy_association" "ip_amd_not_ready_bastion_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.ip_amd_not_ready_eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}
resource "aws_iam_role_policy_attachment" "ip_amd_not_ready_karpenter_controller_iam_role" {
  role       = aws_iam_role.ip_amd_not_ready_karpenter_controller_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_eks_access_policy_association" "missing_loopback_interface_bastion_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.missing_loopback_interface_eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}
resource "aws_iam_role_policy_attachment" "missing_loopback_interface_karpenter_controller_iam_role" {
  role       = aws_iam_role.missing_loopback_interface_karpenter_controller_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_eks_access_policy_association" "pod_stuck_terminating_bastion_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.pod_stuck_terminating_eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}
resource "aws_iam_role_policy_attachment" "pod_stuck_terminating_karpenter_controller_iam_role" {
  role       = aws_iam_role.pod_stuck_terminating_karpenter_controller_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_eks_access_policy_association" "xfs_small_average_cluster_size_bastion_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.xfs_small_average_cluster_size_eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}
resource "aws_iam_role_policy_attachment" "xfs_small_average_cluster_size_karpenter_controller_iam_role" {
  role       = aws_iam_role.xfs_small_average_cluster_size_karpenter_controller_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
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
# #     "Timeout": "PT7M"
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

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource BastionEc2 --region ${data.aws_region.current.region}

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
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc

curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz"
tar -xzf eksctl_$(uname -s)_amd64.tar.gz -C /tmp && rm eksctl_$(uname -s)_amd64.tar.gz
sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

mkdir -p /home/ec2-user/manifests
echo 'apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: "karpenter.k8s.aws/instance-family"
          operator: In
          values: ["t3"]
        - key: "karpenter.k8s.aws/instance-cpu"
          operator: Gt
          values: ["1"]
        - key: "karpenter.k8s.aws/instance-memory"
          operator: Gt
          values: ["2048"]
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["on-demand"]
        - key: "karpenter-nodepool"
          operator: Exists
---
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  subnetSelectorTerms:
    - id: ${aws_subnet.private_subneta.id}
    - id: ${aws_subnet.private_subnetb.id}
  securityGroupSelectorTerms:
    - id: ${aws_security_group.eks_cluster_security_group.id}
  role: ${aws_iam_role.karpenter_node_iam_role.name}
  amiSelectorTerms:
    - alias: al2023@latest
  userData: |
    #!/bin/bash
    timedatectl set-timezone Asia/Seoul
  tags:
    Name: Karpenter-Node' > /home/ec2-user/manifests/nodepool.yaml
echo 'apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: nginx
  name: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      nodeSelector:
        karpenter-nodepool: deafult
      containers:
      - image: nginx
        name: nginx' > /home/ec2-user/manifests/deployment.yaml
EOF
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_ec2_security_group.id, aws_security_group.eks_cluster_security_group.id]
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
resource "aws_eks_cluster" "fork_failed_out_of_p_id_eks_cluster" {
  version = "1.32"
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    subnet_ids              = [aws_subnet.public_subneta.id, aws_subnet.public_subnetb.id, aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
    security_group_ids      = [aws_security_group.eks_cluster_security_group.id]
  }
  role_arn = aws_iam_role.eks_cluster_iam_role.arn
  upgrade_policy {
    support_type = "STANDARD"
  }
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-fork-failed-out-of-p-id-eks-cluster"
}
resource "aws_iam_openid_connect_provider" "fork_failed_out_of_p_id_eks_oidc_provider" {
  url            = aws_eks_cluster.fork_failed_out_of_p_id_eks_cluster.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_eks_access_entry" "fork_failed_out_of_p_id_bastion_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.fork_failed_out_of_p_id_eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  type          = "STANDARD"
}
resource "aws_eks_addon" "fork_failed_out_of_p_id_vpc_cni_addon" {
  addon_name                  = "vpc-cni"
  cluster_name                = aws_eks_cluster.fork_failed_out_of_p_id_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "fork_failed_out_of_p_id_kube_proxy_addon" {
  addon_name                  = "kube-proxy"
  cluster_name                = aws_eks_cluster.fork_failed_out_of_p_id_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "fork_failed_out_of_p_id_coredns_addon" {
  addon_name                  = "coredns"
  cluster_name                = aws_eks_cluster.fork_failed_out_of_p_id_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "fork_failed_out_of_p_id_pod_identity_agent_addon" {
  addon_name                  = "eks-pod-identity-agent"
  cluster_name                = aws_eks_cluster.fork_failed_out_of_p_id_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "fork_failed_out_of_p_id_cloud_watch_observability_addon" {
  addon_name                  = "amazon-cloudwatch-observability"
  cluster_name                = aws_eks_cluster.fork_failed_out_of_p_id_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
  pod_identity_association {
    role_arn        = aws_iam_role.cloud_watch_observability_iam_role.arn
    service_account = "cloudwatch-agent"
  }
  configuration_values = "containerLogs:\n  fluentBit:\n    config:\n      extraFiles:\n        application-log.conf: \"\"\n        dataplane-log.conf: \"\"\n        node-monitoring-agent.conf: |\n          [INPUT]\n            Name                tail\n            Tag                 node-monitoring-agent.*\n            Path                /var/log/containers/eks-node-monitoring-agent-*_kube-system_*.log\n            multiline.parser    docker, cri\n            DB                  /var/fluent-bit/state/flb-node-monitoring-agent.db\n            Mem_Buf_Limit       50MB\n            Skip_Long_Lines     On\n            Refresh_Interval    10\n            Rotate_Wait         30\n            storage.type        filesystem\n            Read_from_Head      $${READ_FROM_HEAD}\n\n          [FILTER]\n            Name                kubernetes\n            Match               node-monitoring-agent.*\n            Kube_Tag_Prefix     node-monitoring-agent.var.log.containers.\n            Kube_URL            https://kubernetes.default.svc:443\n            Merge_Log           On\n            Merge_Log_Key       log_processed\n            K8S-Logging.Parser  On\n            K8S-Logging.Exclude Off\n            Labels              Off\n            Annotations         Off\n            Use_Kubelet         On\n            Kubelet_Port        10250\n            Buffer_Size         0\n            Use_Pod_Association On\n\n          [FILTER]\n            Name                nest\n            Match               node-monitoring-agent.*\n            Operation           lift\n            Nested_under        kubernetes\n\n          [FILTER]\n            Name                modify\n            Match               node-monitoring-agent.*\n            Rename              pod_name pod\n            Rename              container_name container\n            Rename              namespace_name namespace\n            Rename              host node\n\n          [FILTER]\n            Name                record_modifier\n            Match               node-monitoring-agent.*\n            Allowlist_key       log\n            Allowlist_key       pod\n            Allowlist_key       container\n            Allowlist_key       namespace\n            Allowlist_key       node\n\n          [OUTPUT]\n            Name                cloudwatch_logs\n            Match               node-monitoring-agent.*\n            region              $${AWS_REGION}\n            log_group_name      /aws/eks/$${CLUSTER_NAME}/node-monitoring-agent\n            log_stream_prefix   node-monitoring-agent-\n            log_stream_template $pod.FROM.$${HOST_NAME}\n            auto_create_group   true\n            extra_user_agent    container-insights\n            add_entity          true\n"
  depends_on           = [aws_eks_addon.fork_failed_out_of_p_id_pod_identity_agent_addon]
}
resource "aws_eks_addon" "fork_failed_out_of_p_id_node_monitoring_agent_addon" {
  addon_name                  = "eks-node-monitoring-agent"
  cluster_name                = aws_eks_cluster.fork_failed_out_of_p_id_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_node_group" "fork_failed_out_of_p_id_managed_node_group" {
  cluster_name   = aws_eks_cluster.fork_failed_out_of_p_id_eks_cluster.name
  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"
  node_role_arn  = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    min_size     = 3
    desired_size = 3
    max_size     = 3
  }
  subnet_ids = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  launch_template {
    id      = aws_launch_template.fork_failed_out_of_p_id_launch_template.id
    version = aws_launch_template.fork_failed_out_of_p_id_launch_template.latest_version
  }
  node_repair_config {
    enabled = true
  }
}
resource "aws_launch_template" "fork_failed_out_of_p_id_launch_template" {
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_security_group.eks_cluster_security_group.id]
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ForkFailedOutOfPID-Node"
    }
  }
}
resource "aws_iam_role" "fork_failed_out_of_p_id_karpenter_controller_iam_role" {
  assume_role_policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Principal": {
              "Federated": "${aws_iam_openid_connect_provider.fork_failed_out_of_p_id_eks_oidc_provider.arn}"
          },
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Condition": {
              "StringEquals": {
                  "${element(split("//", aws_eks_cluster.fork_failed_out_of_p_id_eks_cluster.identity[0].oidc[0].issuer), 1)}:sub": "system:serviceaccount:kube-system:karpenter",
                  "${element(split("//", aws_eks_cluster.fork_failed_out_of_p_id_eks_cluster.identity[0].oidc[0].issuer), 1)}:aud": "sts.amazonaws.com"
              }
          }
      }
  ]
}
EOT
}
resource "aws_eks_access_entry" "fork_failed_out_of_p_id_karpenter_node_iam_access_entry" {
  cluster_name  = aws_eks_cluster.fork_failed_out_of_p_id_eks_cluster.name
  principal_arn = aws_iam_role.karpenter_node_iam_role.arn
  type          = "EC2_LINUX"
}
resource "aws_ssm_association" "fork_failed_out_of_p_id_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 300
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << 'EOF'\nmkdir -p /home/ec2-user/ForkFailedOutOfPID\necho '#!/bin/bash\naws eks update-kubeconfig --name ${aws_eks_cluster.fork_failed_out_of_p_id_eks_cluster.name}\nexport KARPENTER_NAMESPACE=\"kube-system\"\nexport KARPENTER_VERSION=\"1.6.0\"\nexport K8S_VERSION=\"1.33\"\nexport AWS_PARTITION=\"aws\"\nexport CLUSTER_NAME=\"${aws_eks_cluster.fork_failed_out_of_p_id_eks_cluster.name}\"\nexport AWS_DEFAULT_REGION=\"${data.aws_region.current.region}\"\nexport AWS_ACCOUNT_ID=\"$(aws sts get-caller-identity --query Account --output text)\"\nexport TEMPOUT=\"$(mktemp)\"\nhelm registry logout public.ecr.aws\nhelm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \\\n--version \"$KARPENTER_VERSION\" \\\n--namespace \"$KARPENTER_NAMESPACE\" --create-namespace \\\n--set \"settings.clusterName=$CLUSTER_NAME\" \\\n--set controller.resources.requests.cpu=1 \\\n--set controller.resources.requests.memory=1Gi \\\n--set controller.resources.limits.cpu=1 \\\n--set controller.resources.limits.memory=1Gi \\\n--set settings.featureGates.nodeRepair=true \\\n--set serviceAccount.annotations.\"eks\\.amazonaws\\.com/role-arn\"=\"${aws_iam_role.fork_failed_out_of_p_id_karpenter_controller_iam_role.arn}\" \\\n--wait' > /home/ec2-user/ForkFailedOutOfPID/install_karpenter.sh\nchmod +x /home/ec2-user/ForkFailedOutOfPID/install_karpenter.sh\n# /home/ec2-user/ForkFailedOutOfPID/install_karpenter.sh\n# kubectl apply -f /home/ec2-user/manifests\nEOF\n"])
  }
}
resource "aws_eks_cluster" "interface_not_up_eks_cluster" {
  version = "1.32"
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    subnet_ids              = [aws_subnet.public_subneta.id, aws_subnet.public_subnetb.id, aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
    security_group_ids      = [aws_security_group.eks_cluster_security_group.id]
  }
  role_arn = aws_iam_role.eks_cluster_iam_role.arn
  upgrade_policy {
    support_type = "STANDARD"
  }
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-interface-not-up-eks-cluster"
}
resource "aws_iam_openid_connect_provider" "interface_not_up_eks_oidc_provider" {
  url            = aws_eks_cluster.interface_not_up_eks_cluster.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_eks_access_entry" "interface_not_up_bastion_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.interface_not_up_eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  type          = "STANDARD"
}
resource "aws_eks_addon" "interface_not_up_vpc_cni_addon" {
  addon_name                  = "vpc-cni"
  cluster_name                = aws_eks_cluster.interface_not_up_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "interface_not_up_kube_proxy_addon" {
  addon_name                  = "kube-proxy"
  cluster_name                = aws_eks_cluster.interface_not_up_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "interface_not_up_coredns_addon" {
  addon_name                  = "coredns"
  cluster_name                = aws_eks_cluster.interface_not_up_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "interface_not_up_pod_identity_agent_addon" {
  addon_name                  = "eks-pod-identity-agent"
  cluster_name                = aws_eks_cluster.interface_not_up_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "interface_not_up_cloud_watch_observability_addon" {
  addon_name                  = "amazon-cloudwatch-observability"
  cluster_name                = aws_eks_cluster.interface_not_up_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
  pod_identity_association {
    role_arn        = aws_iam_role.cloud_watch_observability_iam_role.arn
    service_account = "cloudwatch-agent"
  }
  configuration_values = "containerLogs:\n  fluentBit:\n    config:\n      extraFiles:\n        application-log.conf: \"\"\n        dataplane-log.conf: \"\"\n        node-monitoring-agent.conf: |\n          [INPUT]\n            Name                tail\n            Tag                 node-monitoring-agent.*\n            Path                /var/log/containers/eks-node-monitoring-agent-*_kube-system_*.log\n            multiline.parser    docker, cri\n            DB                  /var/fluent-bit/state/flb-node-monitoring-agent.db\n            Mem_Buf_Limit       50MB\n            Skip_Long_Lines     On\n            Refresh_Interval    10\n            Rotate_Wait         30\n            storage.type        filesystem\n            Read_from_Head      $${READ_FROM_HEAD}\n\n          [FILTER]\n            Name                kubernetes\n            Match               node-monitoring-agent.*\n            Kube_Tag_Prefix     node-monitoring-agent.var.log.containers.\n            Kube_URL            https://kubernetes.default.svc:443\n            Merge_Log           On\n            Merge_Log_Key       log_processed\n            K8S-Logging.Parser  On\n            K8S-Logging.Exclude Off\n            Labels              Off\n            Annotations         Off\n            Use_Kubelet         On\n            Kubelet_Port        10250\n            Buffer_Size         0\n            Use_Pod_Association On\n\n          [FILTER]\n            Name                nest\n            Match               node-monitoring-agent.*\n            Operation           lift\n            Nested_under        kubernetes\n\n          [FILTER]\n            Name                modify\n            Match               node-monitoring-agent.*\n            Rename              pod_name pod\n            Rename              container_name container\n            Rename              namespace_name namespace\n            Rename              host node\n\n          [FILTER]\n            Name                record_modifier\n            Match               node-monitoring-agent.*\n            Allowlist_key       log\n            Allowlist_key       pod\n            Allowlist_key       container\n            Allowlist_key       namespace\n            Allowlist_key       node\n\n          [OUTPUT]\n            Name                cloudwatch_logs\n            Match               node-monitoring-agent.*\n            region              $${AWS_REGION}\n            log_group_name      /aws/eks/$${CLUSTER_NAME}/node-monitoring-agent\n            log_stream_prefix   node-monitoring-agent-\n            log_stream_template $pod.FROM.$${HOST_NAME}\n            auto_create_group   true\n            extra_user_agent    container-insights\n            add_entity          true\n"
  depends_on           = [aws_eks_addon.interface_not_up_pod_identity_agent_addon]
}
resource "aws_eks_addon" "interface_not_up_node_monitoring_agent_addon" {
  addon_name                  = "eks-node-monitoring-agent"
  cluster_name                = aws_eks_cluster.interface_not_up_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_node_group" "interface_not_up_managed_node_group" {
  cluster_name   = aws_eks_cluster.interface_not_up_eks_cluster.name
  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"
  node_role_arn  = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    min_size     = 3
    desired_size = 3
    max_size     = 3
  }
  subnet_ids = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  launch_template {
    id      = aws_launch_template.interface_not_up_launch_template.id
    version = aws_launch_template.interface_not_up_launch_template.latest_version
  }
  node_repair_config {
    enabled = true
  }
}
resource "aws_launch_template" "interface_not_up_launch_template" {
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_security_group.eks_cluster_security_group.id]
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "InterfaceNotUp-Node"
    }
  }
}
resource "aws_iam_role" "interface_not_up_karpenter_controller_iam_role" {
  assume_role_policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Principal": {
              "Federated": "${aws_iam_openid_connect_provider.interface_not_up_eks_oidc_provider.arn}"
          },
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Condition": {
              "StringEquals": {
                  "${element(split("//", aws_eks_cluster.interface_not_up_eks_cluster.identity[0].oidc[0].issuer), 1)}:sub": "system:serviceaccount:kube-system:karpenter",
                  "${element(split("//", aws_eks_cluster.interface_not_up_eks_cluster.identity[0].oidc[0].issuer), 1)}:aud": "sts.amazonaws.com"
              }
          }
      }
  ]
}
EOT
}
resource "aws_eks_access_entry" "interface_not_up_karpenter_node_iam_access_entry" {
  cluster_name  = aws_eks_cluster.interface_not_up_eks_cluster.name
  principal_arn = aws_iam_role.karpenter_node_iam_role.arn
  type          = "EC2_LINUX"
}
resource "aws_ssm_association" "interface_not_up_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 300
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << 'EOF'\nmkdir -p /home/ec2-user/InterfaceNotUp\necho '#!/bin/bash\naws eks update-kubeconfig --name ${aws_eks_cluster.interface_not_up_eks_cluster.name}\nexport KARPENTER_NAMESPACE=\"kube-system\"\nexport KARPENTER_VERSION=\"1.6.0\"\nexport K8S_VERSION=\"1.33\"\nexport AWS_PARTITION=\"aws\"\nexport CLUSTER_NAME=\"${aws_eks_cluster.interface_not_up_eks_cluster.name}\"\nexport AWS_DEFAULT_REGION=\"${data.aws_region.current.region}\"\nexport AWS_ACCOUNT_ID=\"$(aws sts get-caller-identity --query Account --output text)\"\nexport TEMPOUT=\"$(mktemp)\"\nhelm registry logout public.ecr.aws\nhelm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \\\n--version \"$KARPENTER_VERSION\" \\\n--namespace \"$KARPENTER_NAMESPACE\" --create-namespace \\\n--set \"settings.clusterName=$CLUSTER_NAME\" \\\n--set controller.resources.requests.cpu=1 \\\n--set controller.resources.requests.memory=1Gi \\\n--set controller.resources.limits.cpu=1 \\\n--set controller.resources.limits.memory=1Gi \\\n--set settings.featureGates.nodeRepair=true \\\n--set serviceAccount.annotations.\"eks\\.amazonaws\\.com/role-arn\"=\"${aws_iam_role.interface_not_up_karpenter_controller_iam_role.arn}\" \\\n--wait' > /home/ec2-user/InterfaceNotUp/install_karpenter.sh\nchmod +x /home/ec2-user/InterfaceNotUp/install_karpenter.sh\n# /home/ec2-user/InterfaceNotUp/install_karpenter.sh\n# kubectl apply -f /home/ec2-user/manifests\nEOF\n"])
  }
}
resource "aws_eks_cluster" "ip_amd_not_ready_eks_cluster" {
  version = "1.32"
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    subnet_ids              = [aws_subnet.public_subneta.id, aws_subnet.public_subnetb.id, aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
    security_group_ids      = [aws_security_group.eks_cluster_security_group.id]
  }
  role_arn = aws_iam_role.eks_cluster_iam_role.arn
  upgrade_policy {
    support_type = "STANDARD"
  }
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-ip-amd-not-ready-eks-cluster"
}
resource "aws_iam_openid_connect_provider" "ip_amd_not_ready_eks_oidc_provider" {
  url            = aws_eks_cluster.ip_amd_not_ready_eks_cluster.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_eks_access_entry" "ip_amd_not_ready_bastion_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.ip_amd_not_ready_eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  type          = "STANDARD"
}
resource "aws_eks_addon" "ip_amd_not_ready_vpc_cni_addon" {
  addon_name                  = "vpc-cni"
  cluster_name                = aws_eks_cluster.ip_amd_not_ready_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "ip_amd_not_ready_kube_proxy_addon" {
  addon_name                  = "kube-proxy"
  cluster_name                = aws_eks_cluster.ip_amd_not_ready_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "ip_amd_not_ready_coredns_addon" {
  addon_name                  = "coredns"
  cluster_name                = aws_eks_cluster.ip_amd_not_ready_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "ip_amd_not_ready_pod_identity_agent_addon" {
  addon_name                  = "eks-pod-identity-agent"
  cluster_name                = aws_eks_cluster.ip_amd_not_ready_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "ip_amd_not_ready_cloud_watch_observability_addon" {
  addon_name                  = "amazon-cloudwatch-observability"
  cluster_name                = aws_eks_cluster.ip_amd_not_ready_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
  pod_identity_association {
    role_arn        = aws_iam_role.cloud_watch_observability_iam_role.arn
    service_account = "cloudwatch-agent"
  }
  configuration_values = "containerLogs:\n  fluentBit:\n    config:\n      extraFiles:\n        application-log.conf: \"\"\n        dataplane-log.conf: \"\"\n        node-monitoring-agent.conf: |\n          [INPUT]\n            Name                tail\n            Tag                 node-monitoring-agent.*\n            Path                /var/log/containers/eks-node-monitoring-agent-*_kube-system_*.log\n            multiline.parser    docker, cri\n            DB                  /var/fluent-bit/state/flb-node-monitoring-agent.db\n            Mem_Buf_Limit       50MB\n            Skip_Long_Lines     On\n            Refresh_Interval    10\n            Rotate_Wait         30\n            storage.type        filesystem\n            Read_from_Head      $${READ_FROM_HEAD}\n\n          [FILTER]\n            Name                kubernetes\n            Match               node-monitoring-agent.*\n            Kube_Tag_Prefix     node-monitoring-agent.var.log.containers.\n            Kube_URL            https://kubernetes.default.svc:443\n            Merge_Log           On\n            Merge_Log_Key       log_processed\n            K8S-Logging.Parser  On\n            K8S-Logging.Exclude Off\n            Labels              Off\n            Annotations         Off\n            Use_Kubelet         On\n            Kubelet_Port        10250\n            Buffer_Size         0\n            Use_Pod_Association On\n\n          [FILTER]\n            Name                nest\n            Match               node-monitoring-agent.*\n            Operation           lift\n            Nested_under        kubernetes\n\n          [FILTER]\n            Name                modify\n            Match               node-monitoring-agent.*\n            Rename              pod_name pod\n            Rename              container_name container\n            Rename              namespace_name namespace\n            Rename              host node\n\n          [FILTER]\n            Name                record_modifier\n            Match               node-monitoring-agent.*\n            Allowlist_key       log\n            Allowlist_key       pod\n            Allowlist_key       container\n            Allowlist_key       namespace\n            Allowlist_key       node\n\n          [OUTPUT]\n            Name                cloudwatch_logs\n            Match               node-monitoring-agent.*\n            region              $${AWS_REGION}\n            log_group_name      /aws/eks/$${CLUSTER_NAME}/node-monitoring-agent\n            log_stream_prefix   node-monitoring-agent-\n            log_stream_template $pod.FROM.$${HOST_NAME}\n            auto_create_group   true\n            extra_user_agent    container-insights\n            add_entity          true\n"
  depends_on           = [aws_eks_addon.ip_amd_not_ready_pod_identity_agent_addon]
}
resource "aws_eks_addon" "ip_amd_not_ready_node_monitoring_agent_addon" {
  addon_name                  = "eks-node-monitoring-agent"
  cluster_name                = aws_eks_cluster.ip_amd_not_ready_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_node_group" "ip_amd_not_ready_managed_node_group" {
  cluster_name   = aws_eks_cluster.ip_amd_not_ready_eks_cluster.name
  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"
  node_role_arn  = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    min_size     = 3
    desired_size = 3
    max_size     = 3
  }
  subnet_ids = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  launch_template {
    id      = aws_launch_template.ip_amd_not_ready_launch_template.id
    version = aws_launch_template.ip_amd_not_ready_launch_template.latest_version
  }
  node_repair_config {
    enabled = true
  }
}
resource "aws_launch_template" "ip_amd_not_ready_launch_template" {
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_security_group.eks_cluster_security_group.id]
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "IPAMDNotReady-Node"
    }
  }
}
resource "aws_iam_role" "ip_amd_not_ready_karpenter_controller_iam_role" {
  assume_role_policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Principal": {
              "Federated": "${aws_iam_openid_connect_provider.ip_amd_not_ready_eks_oidc_provider.arn}"
          },
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Condition": {
              "StringEquals": {
                  "${element(split("//", aws_eks_cluster.ip_amd_not_ready_eks_cluster.identity[0].oidc[0].issuer), 1)}:sub": "system:serviceaccount:kube-system:karpenter",
                  "${element(split("//", aws_eks_cluster.ip_amd_not_ready_eks_cluster.identity[0].oidc[0].issuer), 1)}:aud": "sts.amazonaws.com"
              }
          }
      }
  ]
}
EOT
}
resource "aws_eks_access_entry" "ip_amd_not_ready_karpenter_node_iam_access_entry" {
  cluster_name  = aws_eks_cluster.ip_amd_not_ready_eks_cluster.name
  principal_arn = aws_iam_role.karpenter_node_iam_role.arn
  type          = "EC2_LINUX"
}
resource "aws_ssm_association" "ip_amd_not_ready_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 300
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << 'EOF'\nmkdir -p /home/ec2-user/IPAMDNotReady\necho '#!/bin/bash\naws eks update-kubeconfig --name ${aws_eks_cluster.ip_amd_not_ready_eks_cluster.name}\nexport KARPENTER_NAMESPACE=\"kube-system\"\nexport KARPENTER_VERSION=\"1.6.0\"\nexport K8S_VERSION=\"1.33\"\nexport AWS_PARTITION=\"aws\"\nexport CLUSTER_NAME=\"${aws_eks_cluster.ip_amd_not_ready_eks_cluster.name}\"\nexport AWS_DEFAULT_REGION=\"${data.aws_region.current.region}\"\nexport AWS_ACCOUNT_ID=\"$(aws sts get-caller-identity --query Account --output text)\"\nexport TEMPOUT=\"$(mktemp)\"\nhelm registry logout public.ecr.aws\nhelm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \\\n--version \"$KARPENTER_VERSION\" \\\n--namespace \"$KARPENTER_NAMESPACE\" --create-namespace \\\n--set \"settings.clusterName=$CLUSTER_NAME\" \\\n--set controller.resources.requests.cpu=1 \\\n--set controller.resources.requests.memory=1Gi \\\n--set controller.resources.limits.cpu=1 \\\n--set controller.resources.limits.memory=1Gi \\\n--set settings.featureGates.nodeRepair=true \\\n--set serviceAccount.annotations.\"eks\\.amazonaws\\.com/role-arn\"=\"${aws_iam_role.ip_amd_not_ready_karpenter_controller_iam_role.arn}\" \\\n--wait' > /home/ec2-user/IPAMDNotReady/install_karpenter.sh\nchmod +x /home/ec2-user/IPAMDNotReady/install_karpenter.sh\n# /home/ec2-user/IPAMDNotReady/install_karpenter.sh\n# kubectl apply -f /home/ec2-user/manifests\nEOF\n"])
  }
}
resource "aws_eks_cluster" "missing_loopback_interface_eks_cluster" {
  version = "1.32"
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    subnet_ids              = [aws_subnet.public_subneta.id, aws_subnet.public_subnetb.id, aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
    security_group_ids      = [aws_security_group.eks_cluster_security_group.id]
  }
  role_arn = aws_iam_role.eks_cluster_iam_role.arn
  upgrade_policy {
    support_type = "STANDARD"
  }
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-missing-loopback-interface-eks-cluster"
}
resource "aws_iam_openid_connect_provider" "missing_loopback_interface_eks_oidc_provider" {
  url            = aws_eks_cluster.missing_loopback_interface_eks_cluster.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_eks_access_entry" "missing_loopback_interface_bastion_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.missing_loopback_interface_eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  type          = "STANDARD"
}
resource "aws_eks_addon" "missing_loopback_interface_vpc_cni_addon" {
  addon_name                  = "vpc-cni"
  cluster_name                = aws_eks_cluster.missing_loopback_interface_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "missing_loopback_interface_kube_proxy_addon" {
  addon_name                  = "kube-proxy"
  cluster_name                = aws_eks_cluster.missing_loopback_interface_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "missing_loopback_interface_coredns_addon" {
  addon_name                  = "coredns"
  cluster_name                = aws_eks_cluster.missing_loopback_interface_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "missing_loopback_interface_pod_identity_agent_addon" {
  addon_name                  = "eks-pod-identity-agent"
  cluster_name                = aws_eks_cluster.missing_loopback_interface_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "missing_loopback_interface_cloud_watch_observability_addon" {
  addon_name                  = "amazon-cloudwatch-observability"
  cluster_name                = aws_eks_cluster.missing_loopback_interface_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
  pod_identity_association {
    role_arn        = aws_iam_role.cloud_watch_observability_iam_role.arn
    service_account = "cloudwatch-agent"
  }
  configuration_values = "containerLogs:\n  fluentBit:\n    config:\n      extraFiles:\n        application-log.conf: \"\"\n        dataplane-log.conf: \"\"\n        node-monitoring-agent.conf: |\n          [INPUT]\n            Name                tail\n            Tag                 node-monitoring-agent.*\n            Path                /var/log/containers/eks-node-monitoring-agent-*_kube-system_*.log\n            multiline.parser    docker, cri\n            DB                  /var/fluent-bit/state/flb-node-monitoring-agent.db\n            Mem_Buf_Limit       50MB\n            Skip_Long_Lines     On\n            Refresh_Interval    10\n            Rotate_Wait         30\n            storage.type        filesystem\n            Read_from_Head      $${READ_FROM_HEAD}\n\n          [FILTER]\n            Name                kubernetes\n            Match               node-monitoring-agent.*\n            Kube_Tag_Prefix     node-monitoring-agent.var.log.containers.\n            Kube_URL            https://kubernetes.default.svc:443\n            Merge_Log           On\n            Merge_Log_Key       log_processed\n            K8S-Logging.Parser  On\n            K8S-Logging.Exclude Off\n            Labels              Off\n            Annotations         Off\n            Use_Kubelet         On\n            Kubelet_Port        10250\n            Buffer_Size         0\n            Use_Pod_Association On\n\n          [FILTER]\n            Name                nest\n            Match               node-monitoring-agent.*\n            Operation           lift\n            Nested_under        kubernetes\n\n          [FILTER]\n            Name                modify\n            Match               node-monitoring-agent.*\n            Rename              pod_name pod\n            Rename              container_name container\n            Rename              namespace_name namespace\n            Rename              host node\n\n          [FILTER]\n            Name                record_modifier\n            Match               node-monitoring-agent.*\n            Allowlist_key       log\n            Allowlist_key       pod\n            Allowlist_key       container\n            Allowlist_key       namespace\n            Allowlist_key       node\n\n          [OUTPUT]\n            Name                cloudwatch_logs\n            Match               node-monitoring-agent.*\n            region              $${AWS_REGION}\n            log_group_name      /aws/eks/$${CLUSTER_NAME}/node-monitoring-agent\n            log_stream_prefix   node-monitoring-agent-\n            log_stream_template $pod.FROM.$${HOST_NAME}\n            auto_create_group   true\n            extra_user_agent    container-insights\n            add_entity          true\n"
  depends_on           = [aws_eks_addon.missing_loopback_interface_pod_identity_agent_addon]
}
resource "aws_eks_addon" "missing_loopback_interface_node_monitoring_agent_addon" {
  addon_name                  = "eks-node-monitoring-agent"
  cluster_name                = aws_eks_cluster.missing_loopback_interface_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_node_group" "missing_loopback_interface_managed_node_group" {
  cluster_name   = aws_eks_cluster.missing_loopback_interface_eks_cluster.name
  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"
  node_role_arn  = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    min_size     = 3
    desired_size = 3
    max_size     = 3
  }
  subnet_ids = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  launch_template {
    id      = aws_launch_template.missing_loopback_interface_launch_template.id
    version = aws_launch_template.missing_loopback_interface_launch_template.latest_version
  }
  node_repair_config {
    enabled = true
  }
}
resource "aws_launch_template" "missing_loopback_interface_launch_template" {
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_security_group.eks_cluster_security_group.id]
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "MissingLoopbackInterface-Node"
    }
  }
}
resource "aws_iam_role" "missing_loopback_interface_karpenter_controller_iam_role" {
  assume_role_policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Principal": {
              "Federated": "${aws_iam_openid_connect_provider.missing_loopback_interface_eks_oidc_provider.arn}"
          },
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Condition": {
              "StringEquals": {
                  "${element(split("//", aws_eks_cluster.missing_loopback_interface_eks_cluster.identity[0].oidc[0].issuer), 1)}:sub": "system:serviceaccount:kube-system:karpenter",
                  "${element(split("//", aws_eks_cluster.missing_loopback_interface_eks_cluster.identity[0].oidc[0].issuer), 1)}:aud": "sts.amazonaws.com"
              }
          }
      }
  ]
}
EOT
}
resource "aws_eks_access_entry" "missing_loopback_interface_karpenter_node_iam_access_entry" {
  cluster_name  = aws_eks_cluster.missing_loopback_interface_eks_cluster.name
  principal_arn = aws_iam_role.karpenter_node_iam_role.arn
  type          = "EC2_LINUX"
}
resource "aws_ssm_association" "missing_loopback_interface_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 300
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << 'EOF'\nmkdir -p /home/ec2-user/MissingLoopbackInterface\necho '#!/bin/bash\naws eks update-kubeconfig --name ${aws_eks_cluster.missing_loopback_interface_eks_cluster.name}\nexport KARPENTER_NAMESPACE=\"kube-system\"\nexport KARPENTER_VERSION=\"1.6.0\"\nexport K8S_VERSION=\"1.33\"\nexport AWS_PARTITION=\"aws\"\nexport CLUSTER_NAME=\"${aws_eks_cluster.missing_loopback_interface_eks_cluster.name}\"\nexport AWS_DEFAULT_REGION=\"${data.aws_region.current.region}\"\nexport AWS_ACCOUNT_ID=\"$(aws sts get-caller-identity --query Account --output text)\"\nexport TEMPOUT=\"$(mktemp)\"\nhelm registry logout public.ecr.aws\nhelm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \\\n--version \"$KARPENTER_VERSION\" \\\n--namespace \"$KARPENTER_NAMESPACE\" --create-namespace \\\n--set \"settings.clusterName=$CLUSTER_NAME\" \\\n--set controller.resources.requests.cpu=1 \\\n--set controller.resources.requests.memory=1Gi \\\n--set controller.resources.limits.cpu=1 \\\n--set controller.resources.limits.memory=1Gi \\\n--set settings.featureGates.nodeRepair=true \\\n--set serviceAccount.annotations.\"eks\\.amazonaws\\.com/role-arn\"=\"${aws_iam_role.missing_loopback_interface_karpenter_controller_iam_role.arn}\" \\\n--wait' > /home/ec2-user/MissingLoopbackInterface/install_karpenter.sh\nchmod +x /home/ec2-user/MissingLoopbackInterface/install_karpenter.sh\n# /home/ec2-user/MissingLoopbackInterface/install_karpenter.sh\n# kubectl apply -f /home/ec2-user/manifests\nEOF\n"])
  }
}
resource "aws_eks_cluster" "pod_stuck_terminating_eks_cluster" {
  version = "1.32"
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    subnet_ids              = [aws_subnet.public_subneta.id, aws_subnet.public_subnetb.id, aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
    security_group_ids      = [aws_security_group.eks_cluster_security_group.id]
  }
  role_arn = aws_iam_role.eks_cluster_iam_role.arn
  upgrade_policy {
    support_type = "STANDARD"
  }
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-pod-stuck-terminating-eks-cluster"
}
resource "aws_iam_openid_connect_provider" "pod_stuck_terminating_eks_oidc_provider" {
  url            = aws_eks_cluster.pod_stuck_terminating_eks_cluster.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_eks_access_entry" "pod_stuck_terminating_bastion_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.pod_stuck_terminating_eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  type          = "STANDARD"
}
resource "aws_eks_addon" "pod_stuck_terminating_vpc_cni_addon" {
  addon_name                  = "vpc-cni"
  cluster_name                = aws_eks_cluster.pod_stuck_terminating_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "pod_stuck_terminating_kube_proxy_addon" {
  addon_name                  = "kube-proxy"
  cluster_name                = aws_eks_cluster.pod_stuck_terminating_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "pod_stuck_terminating_coredns_addon" {
  addon_name                  = "coredns"
  cluster_name                = aws_eks_cluster.pod_stuck_terminating_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "pod_stuck_terminating_pod_identity_agent_addon" {
  addon_name                  = "eks-pod-identity-agent"
  cluster_name                = aws_eks_cluster.pod_stuck_terminating_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "pod_stuck_terminating_cloud_watch_observability_addon" {
  addon_name                  = "amazon-cloudwatch-observability"
  cluster_name                = aws_eks_cluster.pod_stuck_terminating_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
  pod_identity_association {
    role_arn        = aws_iam_role.cloud_watch_observability_iam_role.arn
    service_account = "cloudwatch-agent"
  }
  configuration_values = "containerLogs:\n  fluentBit:\n    config:\n      extraFiles:\n        application-log.conf: \"\"\n        dataplane-log.conf: \"\"\n        node-monitoring-agent.conf: |\n          [INPUT]\n            Name                tail\n            Tag                 node-monitoring-agent.*\n            Path                /var/log/containers/eks-node-monitoring-agent-*_kube-system_*.log\n            multiline.parser    docker, cri\n            DB                  /var/fluent-bit/state/flb-node-monitoring-agent.db\n            Mem_Buf_Limit       50MB\n            Skip_Long_Lines     On\n            Refresh_Interval    10\n            Rotate_Wait         30\n            storage.type        filesystem\n            Read_from_Head      $${READ_FROM_HEAD}\n\n          [FILTER]\n            Name                kubernetes\n            Match               node-monitoring-agent.*\n            Kube_Tag_Prefix     node-monitoring-agent.var.log.containers.\n            Kube_URL            https://kubernetes.default.svc:443\n            Merge_Log           On\n            Merge_Log_Key       log_processed\n            K8S-Logging.Parser  On\n            K8S-Logging.Exclude Off\n            Labels              Off\n            Annotations         Off\n            Use_Kubelet         On\n            Kubelet_Port        10250\n            Buffer_Size         0\n            Use_Pod_Association On\n\n          [FILTER]\n            Name                nest\n            Match               node-monitoring-agent.*\n            Operation           lift\n            Nested_under        kubernetes\n\n          [FILTER]\n            Name                modify\n            Match               node-monitoring-agent.*\n            Rename              pod_name pod\n            Rename              container_name container\n            Rename              namespace_name namespace\n            Rename              host node\n\n          [FILTER]\n            Name                record_modifier\n            Match               node-monitoring-agent.*\n            Allowlist_key       log\n            Allowlist_key       pod\n            Allowlist_key       container\n            Allowlist_key       namespace\n            Allowlist_key       node\n\n          [OUTPUT]\n            Name                cloudwatch_logs\n            Match               node-monitoring-agent.*\n            region              $${AWS_REGION}\n            log_group_name      /aws/eks/$${CLUSTER_NAME}/node-monitoring-agent\n            log_stream_prefix   node-monitoring-agent-\n            log_stream_template $pod.FROM.$${HOST_NAME}\n            auto_create_group   true\n            extra_user_agent    container-insights\n            add_entity          true\n"
  depends_on           = [aws_eks_addon.pod_stuck_terminating_pod_identity_agent_addon]
}
resource "aws_eks_addon" "pod_stuck_terminating_node_monitoring_agent_addon" {
  addon_name                  = "eks-node-monitoring-agent"
  cluster_name                = aws_eks_cluster.pod_stuck_terminating_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_node_group" "pod_stuck_terminating_managed_node_group" {
  cluster_name   = aws_eks_cluster.pod_stuck_terminating_eks_cluster.name
  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"
  node_role_arn  = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    min_size     = 3
    desired_size = 3
    max_size     = 3
  }
  subnet_ids = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  launch_template {
    id      = aws_launch_template.pod_stuck_terminating_launch_template.id
    version = aws_launch_template.pod_stuck_terminating_launch_template.latest_version
  }
  node_repair_config {
    enabled = true
  }
}
resource "aws_launch_template" "pod_stuck_terminating_launch_template" {
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_security_group.eks_cluster_security_group.id]
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "PodStuckTerminating-Node"
    }
  }
}
resource "aws_iam_role" "pod_stuck_terminating_karpenter_controller_iam_role" {
  assume_role_policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Principal": {
              "Federated": "${aws_iam_openid_connect_provider.pod_stuck_terminating_eks_oidc_provider.arn}"
          },
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Condition": {
              "StringEquals": {
                  "${element(split("//", aws_eks_cluster.pod_stuck_terminating_eks_cluster.identity[0].oidc[0].issuer), 1)}:sub": "system:serviceaccount:kube-system:karpenter",
                  "${element(split("//", aws_eks_cluster.pod_stuck_terminating_eks_cluster.identity[0].oidc[0].issuer), 1)}:aud": "sts.amazonaws.com"
              }
          }
      }
  ]
}
EOT
}
resource "aws_eks_access_entry" "pod_stuck_terminating_karpenter_node_iam_access_entry" {
  cluster_name  = aws_eks_cluster.pod_stuck_terminating_eks_cluster.name
  principal_arn = aws_iam_role.karpenter_node_iam_role.arn
  type          = "EC2_LINUX"
}
resource "aws_ssm_association" "pod_stuck_terminating_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 300
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << 'EOF'\nmkdir -p /home/ec2-user/PodStuckTerminating\necho '#!/bin/bash\naws eks update-kubeconfig --name ${aws_eks_cluster.pod_stuck_terminating_eks_cluster.name}\nexport KARPENTER_NAMESPACE=\"kube-system\"\nexport KARPENTER_VERSION=\"1.6.0\"\nexport K8S_VERSION=\"1.33\"\nexport AWS_PARTITION=\"aws\"\nexport CLUSTER_NAME=\"${aws_eks_cluster.pod_stuck_terminating_eks_cluster.name}\"\nexport AWS_DEFAULT_REGION=\"${data.aws_region.current.region}\"\nexport AWS_ACCOUNT_ID=\"$(aws sts get-caller-identity --query Account --output text)\"\nexport TEMPOUT=\"$(mktemp)\"\nhelm registry logout public.ecr.aws\nhelm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \\\n--version \"$KARPENTER_VERSION\" \\\n--namespace \"$KARPENTER_NAMESPACE\" --create-namespace \\\n--set \"settings.clusterName=$CLUSTER_NAME\" \\\n--set controller.resources.requests.cpu=1 \\\n--set controller.resources.requests.memory=1Gi \\\n--set controller.resources.limits.cpu=1 \\\n--set controller.resources.limits.memory=1Gi \\\n--set settings.featureGates.nodeRepair=true \\\n--set serviceAccount.annotations.\"eks\\.amazonaws\\.com/role-arn\"=\"${aws_iam_role.pod_stuck_terminating_karpenter_controller_iam_role.arn}\" \\\n--wait' > /home/ec2-user/PodStuckTerminating/install_karpenter.sh\nchmod +x /home/ec2-user/PodStuckTerminating/install_karpenter.sh\n# /home/ec2-user/PodStuckTerminating/install_karpenter.sh\n# kubectl apply -f /home/ec2-user/manifests\nEOF\n"])
  }
}
resource "aws_eks_cluster" "xfs_small_average_cluster_size_eks_cluster" {
  version = "1.32"
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    subnet_ids              = [aws_subnet.public_subneta.id, aws_subnet.public_subnetb.id, aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
    security_group_ids      = [aws_security_group.eks_cluster_security_group.id]
  }
  role_arn = aws_iam_role.eks_cluster_iam_role.arn
  upgrade_policy {
    support_type = "STANDARD"
  }
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-xfs-small-average-cluster-size-eks-cluster"
}
resource "aws_iam_openid_connect_provider" "xfs_small_average_cluster_size_eks_oidc_provider" {
  url            = aws_eks_cluster.xfs_small_average_cluster_size_eks_cluster.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_eks_access_entry" "xfs_small_average_cluster_size_bastion_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.xfs_small_average_cluster_size_eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  type          = "STANDARD"
}
resource "aws_eks_addon" "xfs_small_average_cluster_size_vpc_cni_addon" {
  addon_name                  = "vpc-cni"
  cluster_name                = aws_eks_cluster.xfs_small_average_cluster_size_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "xfs_small_average_cluster_size_kube_proxy_addon" {
  addon_name                  = "kube-proxy"
  cluster_name                = aws_eks_cluster.xfs_small_average_cluster_size_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "xfs_small_average_cluster_size_coredns_addon" {
  addon_name                  = "coredns"
  cluster_name                = aws_eks_cluster.xfs_small_average_cluster_size_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "xfs_small_average_cluster_size_pod_identity_agent_addon" {
  addon_name                  = "eks-pod-identity-agent"
  cluster_name                = aws_eks_cluster.xfs_small_average_cluster_size_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "xfs_small_average_cluster_size_cloud_watch_observability_addon" {
  addon_name                  = "amazon-cloudwatch-observability"
  cluster_name                = aws_eks_cluster.xfs_small_average_cluster_size_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
  pod_identity_association {
    role_arn        = aws_iam_role.cloud_watch_observability_iam_role.arn
    service_account = "cloudwatch-agent"
  }
  configuration_values = "containerLogs:\n  fluentBit:\n    config:\n      extraFiles:\n        application-log.conf: \"\"\n        dataplane-log.conf: \"\"\n        node-monitoring-agent.conf: |\n          [INPUT]\n            Name                tail\n            Tag                 node-monitoring-agent.*\n            Path                /var/log/containers/eks-node-monitoring-agent-*_kube-system_*.log\n            multiline.parser    docker, cri\n            DB                  /var/fluent-bit/state/flb-node-monitoring-agent.db\n            Mem_Buf_Limit       50MB\n            Skip_Long_Lines     On\n            Refresh_Interval    10\n            Rotate_Wait         30\n            storage.type        filesystem\n            Read_from_Head      $${READ_FROM_HEAD}\n\n          [FILTER]\n            Name                kubernetes\n            Match               node-monitoring-agent.*\n            Kube_Tag_Prefix     node-monitoring-agent.var.log.containers.\n            Kube_URL            https://kubernetes.default.svc:443\n            Merge_Log           On\n            Merge_Log_Key       log_processed\n            K8S-Logging.Parser  On\n            K8S-Logging.Exclude Off\n            Labels              Off\n            Annotations         Off\n            Use_Kubelet         On\n            Kubelet_Port        10250\n            Buffer_Size         0\n            Use_Pod_Association On\n\n          [FILTER]\n            Name                nest\n            Match               node-monitoring-agent.*\n            Operation           lift\n            Nested_under        kubernetes\n\n          [FILTER]\n            Name                modify\n            Match               node-monitoring-agent.*\n            Rename              pod_name pod\n            Rename              container_name container\n            Rename              namespace_name namespace\n            Rename              host node\n\n          [FILTER]\n            Name                record_modifier\n            Match               node-monitoring-agent.*\n            Allowlist_key       log\n            Allowlist_key       pod\n            Allowlist_key       container\n            Allowlist_key       namespace\n            Allowlist_key       node\n\n          [OUTPUT]\n            Name                cloudwatch_logs\n            Match               node-monitoring-agent.*\n            region              $${AWS_REGION}\n            log_group_name      /aws/eks/$${CLUSTER_NAME}/node-monitoring-agent\n            log_stream_prefix   node-monitoring-agent-\n            log_stream_template $pod.FROM.$${HOST_NAME}\n            auto_create_group   true\n            extra_user_agent    container-insights\n            add_entity          true\n"
  depends_on           = [aws_eks_addon.xfs_small_average_cluster_size_pod_identity_agent_addon]
}
resource "aws_eks_addon" "xfs_small_average_cluster_size_node_monitoring_agent_addon" {
  addon_name                  = "eks-node-monitoring-agent"
  cluster_name                = aws_eks_cluster.xfs_small_average_cluster_size_eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_node_group" "xfs_small_average_cluster_size_managed_node_group" {
  cluster_name   = aws_eks_cluster.xfs_small_average_cluster_size_eks_cluster.name
  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"
  node_role_arn  = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    min_size     = 3
    desired_size = 3
    max_size     = 3
  }
  subnet_ids = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  launch_template {
    id      = aws_launch_template.xfs_small_average_cluster_size_launch_template.id
    version = aws_launch_template.xfs_small_average_cluster_size_launch_template.latest_version
  }
  node_repair_config {
    enabled = true
  }
}
resource "aws_launch_template" "xfs_small_average_cluster_size_launch_template" {
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_security_group.eks_cluster_security_group.id]
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "XFSSmallAverageClusterSize-Node"
    }
  }
}
resource "aws_iam_role" "xfs_small_average_cluster_size_karpenter_controller_iam_role" {
  assume_role_policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Principal": {
              "Federated": "${aws_iam_openid_connect_provider.xfs_small_average_cluster_size_eks_oidc_provider.arn}"
          },
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Condition": {
              "StringEquals": {
                  "${element(split("//", aws_eks_cluster.xfs_small_average_cluster_size_eks_cluster.identity[0].oidc[0].issuer), 1)}:sub": "system:serviceaccount:kube-system:karpenter",
                  "${element(split("//", aws_eks_cluster.xfs_small_average_cluster_size_eks_cluster.identity[0].oidc[0].issuer), 1)}:aud": "sts.amazonaws.com"
              }
          }
      }
  ]
}
EOT
}
resource "aws_eks_access_entry" "xfs_small_average_cluster_size_karpenter_node_iam_access_entry" {
  cluster_name  = aws_eks_cluster.xfs_small_average_cluster_size_eks_cluster.name
  principal_arn = aws_iam_role.karpenter_node_iam_role.arn
  type          = "EC2_LINUX"
}
resource "aws_ssm_association" "xfs_small_average_cluster_size_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 300
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << 'EOF'\nmkdir -p /home/ec2-user/XFSSmallAverageClusterSize\necho '#!/bin/bash\naws eks update-kubeconfig --name ${aws_eks_cluster.xfs_small_average_cluster_size_eks_cluster.name}\nexport KARPENTER_NAMESPACE=\"kube-system\"\nexport KARPENTER_VERSION=\"1.6.0\"\nexport K8S_VERSION=\"1.33\"\nexport AWS_PARTITION=\"aws\"\nexport CLUSTER_NAME=\"${aws_eks_cluster.xfs_small_average_cluster_size_eks_cluster.name}\"\nexport AWS_DEFAULT_REGION=\"${data.aws_region.current.region}\"\nexport AWS_ACCOUNT_ID=\"$(aws sts get-caller-identity --query Account --output text)\"\nexport TEMPOUT=\"$(mktemp)\"\nhelm registry logout public.ecr.aws\nhelm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \\\n--version \"$KARPENTER_VERSION\" \\\n--namespace \"$KARPENTER_NAMESPACE\" --create-namespace \\\n--set \"settings.clusterName=$CLUSTER_NAME\" \\\n--set controller.resources.requests.cpu=1 \\\n--set controller.resources.requests.memory=1Gi \\\n--set controller.resources.limits.cpu=1 \\\n--set controller.resources.limits.memory=1Gi \\\n--set settings.featureGates.nodeRepair=true \\\n--set serviceAccount.annotations.\"eks\\.amazonaws\\.com/role-arn\"=\"${aws_iam_role.xfs_small_average_cluster_size_karpenter_controller_iam_role.arn}\" \\\n--wait' > /home/ec2-user/XFSSmallAverageClusterSize/install_karpenter.sh\nchmod +x /home/ec2-user/XFSSmallAverageClusterSize/install_karpenter.sh\n# /home/ec2-user/XFSSmallAverageClusterSize/install_karpenter.sh\n# kubectl apply -f /home/ec2-user/manifests\nEOF\n"])
  }
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
resource "aws_security_group" "eks_cluster_security_group" {
  description = "Security Group for EKS Clusters"
  name        = "eks-cluster-sg"
  vpc_id      = aws_vpc.vpc.id
}
resource "aws_vpc_security_group_ingress_rule" "eks_cluster_security_group_ingress" {
  security_group_id            = aws_security_group.eks_cluster_security_group.id
  ip_protocol                  = -1
  referenced_security_group_id = aws_security_group.eks_cluster_security_group.id
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
